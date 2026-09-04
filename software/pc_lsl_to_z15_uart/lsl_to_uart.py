#!/usr/bin/env python3
"""Forward raw LSL EEG sample positions 0..7 to Z15 UART as EEG v0 frames."""

from __future__ import annotations

import argparse
import sys
import time

from protocol import CHANNEL_COUNT, SAMPLES_PER_FRAME, encode_frame


def resolve_eeg_stream(name: str, timeout_s: float):
    from pylsl import StreamInlet, resolve_byprop

    streams = resolve_byprop("name", name, timeout=timeout_s)
    if not streams:
        raise RuntimeError(f"no LSL stream named {name!r} was discovered")
    info = streams[0]
    if info.channel_count() < CHANNEL_COUNT:
        raise RuntimeError(
            f"LSL stream has {info.channel_count()} channel(s); need at least {CHANNEL_COUNT}"
        )
    return StreamInlet(info, max_chunklen=SAMPLES_PER_FRAME), info


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="PC serial port connected to Z15 CH340")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate (default: 115200)")
    parser.add_argument("--stream-name", default="obci_eeg1", help="exact OpenBCI LSL stream name")
    parser.add_argument("--resolve-timeout", type=float, default=5.0)
    args = parser.parse_args()

    try:
        import serial
    except ImportError as exc:
        raise SystemExit("pyserial is required; install requirements.txt") from exc

    inlet, info = resolve_eeg_stream(args.stream_name, args.resolve_timeout)
    print(
        f"LSL stream: name={info.name()!r}, type={info.type()!r}, "
        f"channels={info.channel_count()}, nominal_srate={info.nominal_srate()}"
    )
    print("Transport order: sample positions 0..7 -> Ch1..Ch8 (ordinal labels only)")

    sequence = 0
    clipped_total = 0
    pending: list[list[float]] = []
    first_timestamp: float | None = None
    with serial.Serial(args.port, args.baud, timeout=1, write_timeout=1) as uart:
        print(f"UART open: {args.port} at {args.baud} bit/s")
        while True:
            sample, timestamp = inlet.pull_sample(timeout=1.0)
            if sample is None:
                continue
            if len(sample) < CHANNEL_COUNT:
                print("warning: short LSL sample discarded", file=sys.stderr)
                continue
            if first_timestamp is None:
                first_timestamp = float(timestamp)
            pending.append([float(value) for value in sample[:CHANNEL_COUNT]])
            if len(pending) != SAMPLES_PER_FRAME:
                continue

            frame, clipped = encode_frame(sequence, int(round(first_timestamp * 1_000_000_000)), pending)
            uart.write(frame)
            uart.flush()
            clipped_total += clipped
            print(
                f"sent seq={sequence} bytes={len(frame)} clipped={clipped} "
                f"clipped_total={clipped_total} wall={time.time():.3f}"
            )
            sequence = (sequence + 1) & 0xFFFFFFFF
            pending = []
            first_timestamp = None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
