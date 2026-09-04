#include "eeg_transport_v0.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void write_u16_le(uint8_t *out, uint16_t value) {
    out[0] = (uint8_t)value;
    out[1] = (uint8_t)(value >> 8U);
}

static void write_u32_le(uint8_t *out, uint32_t value) {
    unsigned int index;
    for (index = 0U; index < 4U; ++index) {
        out[index] = (uint8_t)(value >> (index * 8U));
    }
}

static void write_u64_le(uint8_t *out, uint64_t value) {
    unsigned int index;
    for (index = 0U; index < 8U; ++index) {
        out[index] = (uint8_t)(value >> (index * 8U));
    }
}

static uint32_t crc32_ieee(const uint8_t *bytes, size_t length) {
    uint32_t crc = 0xFFFFFFFFU;
    size_t index;
    for (index = 0U; index < length; ++index) {
        unsigned int bit;
        crc ^= bytes[index];
        for (bit = 0U; bit < 8U; ++bit) {
            crc = (crc >> 1U) ^ ((crc & 1U) != 0U ? 0xEDB88320U : 0U);
        }
    }
    return ~crc;
}

static void make_frame(uint8_t frame[GL_EEG_V0_FRAME_BYTES], uint32_t sequence, uint64_t timestamp_ns) {
    uint32_t sample;
    uint32_t channel;
    memset(frame, 0, GL_EEG_V0_FRAME_BYTES);
    memcpy(frame, "GLEE", 4U);
    frame[4] = 1U;
    frame[5] = GL_EEG_V0_HEADER_BYTES;
    write_u32_le(&frame[8], sequence);
    write_u64_le(&frame[12], timestamp_ns);
    write_u16_le(&frame[20], GL_EEG_V0_SAMPLES_PER_FRAME);
    frame[22] = GL_EEG_V0_CHANNELS;
    frame[23] = 1U;
    write_u32_le(&frame[24], 250000U);
    write_u32_le(&frame[28], GL_EEG_V0_SCALE_NV_PER_LSB);
    for (sample = 0U; sample < GL_EEG_V0_SAMPLES_PER_FRAME; ++sample) {
        for (channel = 0U; channel < GL_EEG_V0_CHANNELS; ++channel) {
            const size_t offset = GL_EEG_V0_HEADER_BYTES +
                ((size_t)sample * GL_EEG_V0_CHANNELS + channel) * 2U;
            write_u16_le(&frame[offset], (uint16_t)(sample * 10U + channel));
        }
    }
    write_u32_le(&frame[GL_EEG_V0_FRAME_BYTES - 4U], crc32_ieee(frame, GL_EEG_V0_FRAME_BYTES - 4U));
}

int main(void) {
    gl_eeg_receiver_t receiver;
    uint8_t first[GL_EEG_V0_FRAME_BYTES];
    uint8_t third[GL_EEG_V0_FRAME_BYTES];
    int16_t channels[GL_EEG_V0_CHANNELS];
    uint64_t timestamp;

    make_frame(first, 10U, 1_000_000_000ULL);
    make_frame(third, 12U, 1_200_000_000ULL);
    gl_eeg_receiver_init(&receiver);
    assert(gl_eeg_receiver_feed(&receiver, first, 17U) == 0U);
    assert(gl_eeg_receiver_feed(&receiver, first + 17U, sizeof(first) - 17U) == 1U);
    assert(gl_eeg_receiver_feed(&receiver, third, sizeof(third)) == 1U);
    assert(receiver.stats.frames_ok == 2U);
    assert(receiver.stats.sequence_gaps == 1U);
    assert(receiver.ring.count == 50U);
    assert(gl_eeg_ring_get(&receiver.ring, 0U, channels, &timestamp));
    assert(timestamp == 1_000_000_000ULL);
    assert(channels[0] == 0);
    assert(channels[7] == 7);
    assert(gl_eeg_estimated_sample_rate_hz(&receiver.stats) == 250.0);

    third[40] ^= 1U;
    assert(gl_eeg_receiver_feed(&receiver, third, sizeof(third)) == 0U);
    assert(receiver.stats.crc_errors == 1U);
    puts("eeg_transport_v0 host test: PASS");
    return 0;
}
