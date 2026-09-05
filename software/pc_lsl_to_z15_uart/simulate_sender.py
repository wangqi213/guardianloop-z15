#!/usr/bin/env python3
"""Send deterministic synthetic EEG v0 packets to Z15 without OpenBCI/LSL."""

from __future__ import annotations

import argparse
import math
import time

from protocol import CHANNEL_COUNT, SAMPLE_RATE_HZ, SAMPLES_PER_FRAME, encode_frame


def make_frame_samples(start_index: int) -> list[list[float]]:
    """Eight distinct sine waves expressed in transport input microvolts."""
    samples: list[list[float]] = []
    for sample_offset in range(SAMPLES_PER_FRAME):
        sample_index = start_index + sample_offset
        samples.append(
            [
                50.0
                * math.sin(2.0 * math.pi * (8.0 + channel) * sample_index / SAMPLE_RATE_HZ)
                for channel in range(CHANNEL_COUNT)
            ]
        )
    return samples


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="PC serial port connected to Z15 CH340")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--frames", type=int, default=0, help="number of frames; 0 means continuous")
    parser.add_argument(
        "--chunk-bytes",
        type=int,
        default=0,
        help="test mode: split each frame into chunks; 0 sends one complete frame",
    )
    parser.add_argument(
        "--chunk-gap-ms",
        type=float,
        default=0.0,
        help="test mode: delay between chunks in milliseconds",
    )
    args = parser.parse_args()
    if args.frames < 0:
        raise SystemExit("--frames must be zero or positive")
    if args.chunk_bytes < 0 or args.chunk_gap_ms < 0.0:
        raise SystemExit("chunk size and gap must not be negative")

    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required; install requirements.txt") from exc

    sequence = 0
    sample_index = 0
    next_send = time.monotonic()
    with serial.Serial(args.port, args.baud, timeout=1, write_timeout=1) as uart:
        print(f"UART open: {args.port} at {args.baud} bit/s")
        while args.frames == 0 or sequence < args.frames:
            source_timestamp_ns = time.monotonic_ns()
            packet, clipped = encode_frame(
                sequence, source_timestamp_ns, make_frame_samples(sample_index)
            )
            if args.chunk_bytes == 0:
                uart.write(packet)
                uart.flush()
            else:
                for offset in range(0, len(packet), args.chunk_bytes):
                    uart.write(packet[offset : offset + args.chunk_bytes])
                    uart.flush()
                    if args.chunk_gap_ms != 0.0:
                        time.sleep(args.chunk_gap_ms / 1000.0)
            print(f"sent synthetic seq={sequence} bytes={len(packet)} clipped={clipped}")
            sequence = (sequence + 1) & 0xFFFFFFFF
            sample_index += SAMPLES_PER_FRAME
            next_send += SAMPLES_PER_FRAME / SAMPLE_RATE_HZ
            time.sleep(max(0.0, next_send - time.monotonic()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
