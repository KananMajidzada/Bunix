// tone - the sound card's device file, end to end.
//
// The card is two files like every other piece of the machine: /dev/audioctl
// says the format, and writing samples to /dev/audio plays them. This program
// sets a format, plays a 440 Hz tone for a moment, and stops. It proves that a
// program needs nothing of the sound hardware beyond a write.
//
// It is also the smallest example of the interface a port uses: a game that
// already writes its frames to /dev/fb writes its samples here.

#include <stdint.h>
#include <stdio.h>

#include <dev.h>

// One cycle of a sine wave, sixty-four steps, at a comfortable amplitude.
static const int16_t sine[64] = {
    0, 1960, 3902, 5806, 7654, 9428, 11111, 12688,
    14142, 15460, 16629, 17638, 18478, 19139, 19616, 19904,
    20000, 19904, 19616, 19139, 18478, 17638, 16629, 15460,
    14142, 12688, 11111, 9428, 7654, 5806, 3902, 1960,
    0, -1960, -3902, -5806, -7654, -9428, -11111, -12688,
    -14142, -15460, -16629, -17638, -18478, -19139, -19616, -19904,
    -20000, -19904, -19616, -19139, -18478, -17638, -16629, -15460,
    -14142, -12688, -11111, -9428, -7654, -5806, -3902, -1960,
};

#define RATE 44100
#define HZ 440

int main(void) {
    if (bunix_audio_format(RATE, 1, 16) != 0) {
        printf("tone: this machine has no sound card\n");
        return 1;
    }

    // The phase is a fraction of a cycle in the top bits and the fraction
    // below, so the pitch does not drift the way an integer step would.
    const uint32_t step = (uint32_t)(((uint64_t)64 * HZ * 65536) / RATE);
    uint32_t phase = 0;

    int16_t buf[1024];
    const uint32_t total = RATE;  // one second
    for (uint32_t done = 0; done < total; done += 1024) {
        uint32_t n = total - done;
        if (n > 1024) n = 1024;
        for (uint32_t i = 0; i < n; i++) {
            buf[i] = sine[(phase >> 16) & 63];
            phase += step;
        }
        bunix_audio_write(buf, (size_t)n * sizeof(int16_t));
    }

    // The card plays behind the program, so let the last block finish
    // before the program leaves and its sound is stopped with it.
    bunix_sleepms(500);
    bunix_audio_stop();
    printf("tone: played %d Hz for a second\n", HZ);
    return 0;
}
