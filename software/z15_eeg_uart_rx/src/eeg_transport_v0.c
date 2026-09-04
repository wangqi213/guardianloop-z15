#include "eeg_transport_v0.h"

#include <string.h>

#define GL_EEG_MAGIC_0 'G'
#define GL_EEG_MAGIC_1 'L'
#define GL_EEG_MAGIC_2 'E'
#define GL_EEG_MAGIC_3 'E'
#define GL_EEG_VERSION 1U
#define GL_EEG_SAMPLE_FORMAT_INT16_LE 1U
#define GL_EEG_SAMPLE_RATE_MILLIHZ 250000U

static uint16_t read_u16_le(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t read_u32_le(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static uint64_t read_u64_le(const uint8_t *bytes) {
    uint64_t value = 0U;
    unsigned int index;
    for (index = 0U; index < 8U; ++index) {
        value |= ((uint64_t)bytes[index]) << (index * 8U);
    }
    return value;
}

static uint32_t crc32_ieee(const uint8_t *bytes, size_t length) {
    uint32_t crc = 0xFFFFFFFFU;
    size_t index;
    for (index = 0U; index < length; ++index) {
        uint32_t bit;
        crc ^= bytes[index];
        for (bit = 0U; bit < 8U; ++bit) {
            crc = (crc >> 1U) ^ ((crc & 1U) != 0U ? 0xEDB88320U : 0U);
        }
    }
    return ~crc;
}

static bool has_valid_header(const uint8_t *frame) {
    return frame[0] == GL_EEG_MAGIC_0 && frame[1] == GL_EEG_MAGIC_1 &&
           frame[2] == GL_EEG_MAGIC_2 && frame[3] == GL_EEG_MAGIC_3 &&
           frame[4] == GL_EEG_VERSION && frame[5] == GL_EEG_V0_HEADER_BYTES &&
           read_u16_le(&frame[20]) == GL_EEG_V0_SAMPLES_PER_FRAME &&
           frame[22] == GL_EEG_V0_CHANNELS && frame[23] == GL_EEG_SAMPLE_FORMAT_INT16_LE &&
           read_u32_le(&frame[24]) == GL_EEG_SAMPLE_RATE_MILLIHZ &&
           read_u32_le(&frame[28]) == GL_EEG_V0_SCALE_NV_PER_LSB;
}

static void append_frame(gl_eeg_receiver_t *receiver) {
    const uint8_t *frame = receiver->bytes;
    const uint32_t sequence = read_u32_le(&frame[8]);
    const uint64_t timestamp_ns = read_u64_le(&frame[12]);
    uint32_t sample_index;

    if (receiver->stats.have_sequence) {
        const uint32_t expected = receiver->stats.last_sequence + 1U;
        if (sequence != expected) {
            receiver->stats.sequence_gaps += sequence - expected;
        }
    }
    receiver->stats.have_sequence = true;
    receiver->stats.last_sequence = sequence;
    if (receiver->stats.frames_ok == 0U) {
        receiver->stats.first_source_timestamp_ns = timestamp_ns;
    }
    receiver->stats.last_source_timestamp_ns = timestamp_ns;
    receiver->stats.source_samples_seen += GL_EEG_V0_SAMPLES_PER_FRAME;
    receiver->stats.frames_ok++;

    for (sample_index = 0U; sample_index < GL_EEG_V0_SAMPLES_PER_FRAME; ++sample_index) {
        uint32_t channel;
        const uint32_t ring_index = receiver->ring.write_index;
        const uint64_t sample_time = timestamp_ns +
            ((uint64_t)sample_index * 1000000000ULL) / GL_EEG_V0_SAMPLE_RATE_HZ;
        for (channel = 0U; channel < GL_EEG_V0_CHANNELS; ++channel) {
            const size_t offset = GL_EEG_V0_HEADER_BYTES +
                ((size_t)sample_index * GL_EEG_V0_CHANNELS + channel) * 2U;
            receiver->ring.samples[ring_index][channel] = (int16_t)read_u16_le(&frame[offset]);
        }
        receiver->ring.timestamps_ns[ring_index] = sample_time;
        receiver->ring.write_index = (ring_index + 1U) % GL_EEG_RING_SAMPLES;
        if (receiver->ring.count < GL_EEG_RING_SAMPLES) {
            receiver->ring.count++;
        }
    }
}

void gl_eeg_receiver_init(gl_eeg_receiver_t *receiver) {
    memset(receiver, 0, sizeof(*receiver));
}

uint32_t gl_eeg_receiver_feed(gl_eeg_receiver_t *receiver, const uint8_t *data, size_t length) {
    uint32_t frames_accepted = 0U;
    size_t index;
    for (index = 0U; index < length; ++index) {
        receiver->bytes[receiver->bytes_used++] = data[index];
        for (;;) {
            if (receiver->bytes_used < 4U) {
                break;
            }
            if (receiver->bytes[0] != GL_EEG_MAGIC_0 || receiver->bytes[1] != GL_EEG_MAGIC_1 ||
                receiver->bytes[2] != GL_EEG_MAGIC_2 || receiver->bytes[3] != GL_EEG_MAGIC_3) {
                memmove(receiver->bytes, &receiver->bytes[1], --receiver->bytes_used);
                receiver->stats.bytes_discarded++;
                continue;
            }
            if (receiver->bytes_used < GL_EEG_V0_FRAME_BYTES) {
                break;
            }
            if (!has_valid_header(receiver->bytes)) {
                receiver->stats.format_errors++;
            } else if (crc32_ieee(receiver->bytes, GL_EEG_V0_FRAME_BYTES - GL_EEG_V0_CRC_BYTES) !=
                       read_u32_le(&receiver->bytes[GL_EEG_V0_FRAME_BYTES - GL_EEG_V0_CRC_BYTES])) {
                receiver->stats.crc_errors++;
            } else {
                append_frame(receiver);
                frames_accepted++;
                receiver->bytes_used = 0U;
                break;
            }
            /* Retain the trailing bytes so a later in-buffer magic can sync. */
            memmove(receiver->bytes, &receiver->bytes[1], --receiver->bytes_used);
            receiver->stats.bytes_discarded++;
        }
    }
    return frames_accepted;
}

bool gl_eeg_ring_get(
    const gl_eeg_ring_t *ring,
    uint32_t age,
    int16_t out_channels[GL_EEG_V0_CHANNELS],
    uint64_t *out_timestamp_ns
) {
    uint32_t start;
    uint32_t index;
    if (age >= ring->count) {
        return false;
    }
    start = (ring->write_index + GL_EEG_RING_SAMPLES - ring->count) % GL_EEG_RING_SAMPLES;
    index = (start + age) % GL_EEG_RING_SAMPLES;
    memcpy(out_channels, ring->samples[index], sizeof(ring->samples[index]));
    if (out_timestamp_ns != NULL) {
        *out_timestamp_ns = ring->timestamps_ns[index];
    }
    return true;
}

double gl_eeg_estimated_sample_rate_hz(const gl_eeg_stats_t *stats) {
    const uint64_t elapsed_ns = stats->last_source_timestamp_ns - stats->first_source_timestamp_ns;
    if (stats->frames_ok < 2U || elapsed_ns == 0U) {
        return 0.0;
    }
    return ((double)(stats->source_samples_seen - GL_EEG_V0_SAMPLES_PER_FRAME) * 1000000000.0) /
           (double)elapsed_ns;
}
