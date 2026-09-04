"""GuardianLoop EEG transport v0 binary packet codec.

The protocol intentionally contains no OpenBCI device-control or fatigue
classification logic.  Samples are carried in their LSL arrival order.
"""

from __future__ import annotations

from dataclasses import dataclass
import struct
import zlib

MAGIC = b"GLEE"
VERSION = 1
HEADER_SIZE = 32
CHANNEL_COUNT = 8
SAMPLES_PER_FRAME = 25
SAMPLE_RATE_HZ = 250
SAMPLE_RATE_MILLIHZ = SAMPLE_RATE_HZ * 1000
SAMPLE_FORMAT_INT16_LE = 1
SCALE_NV_PER_LSB = 10
MICROVOLTS_PER_LSB = SCALE_NV_PER_LSB / 1000.0

# magic, version, header bytes, flags, sequence, source timestamp (ns),
# samples, channels, sample format, sample rate (mHz), scale (nV/LSB)
_HEADER = struct.Struct("<4sBBHIQHBBII")
_CRC = struct.Struct("<I")
FRAME_SIZE = HEADER_SIZE + SAMPLES_PER_FRAME * CHANNEL_COUNT * 2 + _CRC.size


class FrameError(ValueError):
    """Raised when an EEG transport v0 frame is malformed."""


@dataclass(frozen=True)
class DecodedFrame:
    sequence: int
    source_timestamp_ns: int
    samples: tuple[tuple[int, ...], ...]
    flags: int


def microvolts_to_int16(value_uv: float) -> tuple[int, bool]:
    """Scale microvolts to 10 nV/LSB signed int16, with deterministic clamp."""
    scaled = int(round(value_uv / MICROVOLTS_PER_LSB))
    if scaled > 32767:
        return 32767, True
    if scaled < -32768:
        return -32768, True
    return scaled, False


def encode_frame(
    sequence: int,
    source_timestamp_ns: int,
    samples_uv: list[list[float]],
    *,
    flags: int = 0,
) -> tuple[bytes, int]:
    """Return one exact v0 packet and the number of clipped input values."""
    if len(samples_uv) != SAMPLES_PER_FRAME:
        raise FrameError(f"expected {SAMPLES_PER_FRAME} samples, got {len(samples_uv)}")

    payload_values: list[int] = []
    clipped = 0
    for sample in samples_uv:
        if len(sample) < CHANNEL_COUNT:
            raise FrameError(f"expected at least {CHANNEL_COUNT} channels per sample")
        for value_uv in sample[:CHANNEL_COUNT]:
            value, was_clipped = microvolts_to_int16(float(value_uv))
            payload_values.append(value)
            clipped += int(was_clipped)

    header = _HEADER.pack(
        MAGIC,
        VERSION,
        HEADER_SIZE,
        flags & 0xFFFF,
        sequence & 0xFFFFFFFF,
        source_timestamp_ns & 0xFFFFFFFFFFFFFFFF,
        SAMPLES_PER_FRAME,
        CHANNEL_COUNT,
        SAMPLE_FORMAT_INT16_LE,
        SAMPLE_RATE_MILLIHZ,
        SCALE_NV_PER_LSB,
    )
    payload = struct.pack("<" + "h" * len(payload_values), *payload_values)
    body = header + payload
    return body + _CRC.pack(zlib.crc32(body) & 0xFFFFFFFF), clipped


def decode_frame(frame: bytes) -> DecodedFrame:
    """Validate and decode one complete fixed-length v0 packet."""
    if len(frame) != FRAME_SIZE:
        raise FrameError(f"expected {FRAME_SIZE} bytes, got {len(frame)}")
    if zlib.crc32(frame[:-_CRC.size]) & 0xFFFFFFFF != _CRC.unpack(frame[-4:])[0]:
        raise FrameError("CRC32 mismatch")

    (
        magic,
        version,
        header_size,
        flags,
        sequence,
        source_timestamp_ns,
        sample_count,
        channel_count,
        sample_format,
        sample_rate_millihz,
        scale_nv_per_lsb,
    ) = _HEADER.unpack(frame[:HEADER_SIZE])
    if magic != MAGIC or version != VERSION or header_size != HEADER_SIZE:
        raise FrameError("unsupported frame header")
    if (
        sample_count != SAMPLES_PER_FRAME
        or channel_count != CHANNEL_COUNT
        or sample_format != SAMPLE_FORMAT_INT16_LE
        or sample_rate_millihz != SAMPLE_RATE_MILLIHZ
        or scale_nv_per_lsb != SCALE_NV_PER_LSB
    ):
        raise FrameError("unsupported frame layout")

    values = struct.unpack("<" + "h" * (sample_count * channel_count), frame[HEADER_SIZE:-4])
    samples = tuple(
        tuple(values[index : index + channel_count])
        for index in range(0, len(values), channel_count)
    )
    return DecodedFrame(sequence, source_timestamp_ns, samples, flags)
