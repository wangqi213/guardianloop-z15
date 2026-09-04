import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from protocol import FRAME_SIZE, FrameError, decode_frame, encode_frame


class ProtocolTests(unittest.TestCase):
    def test_round_trip_is_little_endian_and_fixed_size(self):
        samples = [[channel + point / 10.0 for channel in range(8)] for point in range(25)]
        packet, clipped = encode_frame(7, 123_456_789, samples)
        decoded = decode_frame(packet)
        self.assertEqual(FRAME_SIZE, 436)
        self.assertEqual(len(packet), FRAME_SIZE)
        self.assertEqual(clipped, 0)
        self.assertEqual(decoded.sequence, 7)
        self.assertEqual(decoded.source_timestamp_ns, 123_456_789)
        self.assertEqual(decoded.samples[0][0], 0)
        self.assertEqual(decoded.samples[0][1], 100)

    def test_crc_rejects_corruption(self):
        packet, _ = encode_frame(0, 0, [[0.0] * 8 for _ in range(25)])
        corrupted = bytearray(packet)
        corrupted[33] ^= 0x01
        with self.assertRaises(FrameError):
            decode_frame(bytes(corrupted))

    def test_scaling_clamps_to_int16(self):
        packet, clipped = encode_frame(0, 0, [[1000.0] * 8 for _ in range(25)])
        self.assertEqual(clipped, 200)
        self.assertEqual(decode_frame(packet).samples[0][0], 32767)


if __name__ == "__main__":
    unittest.main()
