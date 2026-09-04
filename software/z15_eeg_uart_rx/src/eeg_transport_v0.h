#ifndef GUARDIANLOOP_EEG_TRANSPORT_V0_H
#define GUARDIANLOOP_EEG_TRANSPORT_V0_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {
    GL_EEG_V0_CHANNELS = 8,
    GL_EEG_V0_SAMPLES_PER_FRAME = 25,
    GL_EEG_V0_SAMPLE_RATE_HZ = 250,
    GL_EEG_V0_SCALE_NV_PER_LSB = 10,
    GL_EEG_V0_HEADER_BYTES = 32,
    GL_EEG_V0_PAYLOAD_BYTES = GL_EEG_V0_SAMPLES_PER_FRAME * GL_EEG_V0_CHANNELS * 2,
    GL_EEG_V0_CRC_BYTES = 4,
    GL_EEG_V0_FRAME_BYTES = GL_EEG_V0_HEADER_BYTES + GL_EEG_V0_PAYLOAD_BYTES + GL_EEG_V0_CRC_BYTES,
    GL_EEG_RING_SAMPLES = GL_EEG_V0_SAMPLE_RATE_HZ * 8
};

typedef struct {
    uint32_t frames_ok;
    uint32_t crc_errors;
    uint32_t format_errors;
    uint32_t sequence_gaps;
    uint32_t bytes_discarded;
    uint32_t last_sequence;
    bool have_sequence;
    uint64_t first_source_timestamp_ns;
    uint64_t last_source_timestamp_ns;
    uint32_t source_samples_seen;
} gl_eeg_stats_t;

typedef struct {
    int16_t samples[GL_EEG_RING_SAMPLES][GL_EEG_V0_CHANNELS];
    uint64_t timestamps_ns[GL_EEG_RING_SAMPLES];
    uint32_t write_index;
    uint32_t count;
} gl_eeg_ring_t;

typedef struct {
    uint8_t bytes[GL_EEG_V0_FRAME_BYTES];
    size_t bytes_used;
    gl_eeg_stats_t stats;
    gl_eeg_ring_t ring;
} gl_eeg_receiver_t;

void gl_eeg_receiver_init(gl_eeg_receiver_t *receiver);

/* Feed arbitrary UART byte chunks. Returns the number of accepted frames. */
uint32_t gl_eeg_receiver_feed(gl_eeg_receiver_t *receiver, const uint8_t *data, size_t length);

/* Get one sample by age: 0 is the oldest retained sample. */
bool gl_eeg_ring_get(
    const gl_eeg_ring_t *ring,
    uint32_t age,
    int16_t out_channels[GL_EEG_V0_CHANNELS],
    uint64_t *out_timestamp_ns
);

/* Zero when timestamps are unavailable or too short; otherwise samples/s. */
double gl_eeg_estimated_sample_rate_hz(const gl_eeg_stats_t *stats);

#endif
