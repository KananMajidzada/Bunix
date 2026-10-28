// fbtest - the drawing program's device files, end to end.
//
// The screen's size comes from /proc/fb, its pixels go to /dev/fb, the clock
// paces the frames from /proc/millis, and key edges arrive from /dev/kbd. The
// screen is saved first and put back at the end, so a session leaves the
// desktop as it was found. Anything wrong prints WRONG:, so the serial log
// tells the whole story without needing the picture.
//
// The picture helps anyway: bands of color fill the screen, a white bar
// sweeps a dark band with the milliseconds, and every key edge lights a
// block along the bottom, green as it goes down and red as it comes up, one
// column per scancode.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <dev.h>

static int fails;

static void wrong(const char *what) {
    printf("WRONG: fbtest %s\n", what);
    fails++;
}

int main(void) {
    uint32_t w = 0, h = 0;
    if (bunix_fb_dims(&w, &h) != 0) {
        printf("fbtest: no framebuffer\n");
        return 1;
    }
    printf("fbtest: screen %ux%u\n", w, h);

    size_t bytes = (size_t)w * h * 4;
    uint32_t *frame = malloc(bytes);
    uint32_t *saved = malloc(bytes);
    if (!frame || !saved) {
        printf("WRONG: fbtest out of memory\n");
        return 1;
    }

    // What the screen shows now, to be put back at the end. Reading it back
    // is the same file the drawing goes to.
    if (bunix_fb_read(0, saved, bytes) != (ssize_t)bytes) {
        wrong("saving the screen");
    }

    // Frame one: bands of color across the whole screen, written whole.
    for (uint32_t y = 0; y < h; y++) {
        uint32_t c = ((y * 255) / h) << 8;
        for (uint32_t x = 0; x < w; x++) {
            frame[y * w + x] = c | ((x * 255) / w);
        }
    }
    if (bunix_fb_write(0, frame, bytes) != (ssize_t)bytes) {
        wrong("writing frame one");
    }

    // The clock: sleep against /proc/millis, then sweep a bar whose position
    // is read from it. The bar's band is written at an offset, a band of rows
    // without touching the rest of the screen.
    uint64_t t0 = bunix_millis();
    bunix_sleepms(400);
    uint64_t t1 = bunix_millis();
    if (t1 - t0 < 350 || t1 - t0 > 3000) {
        wrong("the clock did not advance by about 400ms");
    }
    printf("fbtest: slept %ld ms\n", (long)(t1 - t0));

    const uint32_t band = h / 2;
    const size_t bandbytes = (size_t)band * w * 4;
    for (int step = 0; step < 20; step++) {
        uint32_t bar = (uint32_t)(((bunix_millis() - t0) / 10) % w);
        uint32_t *p = frame + (size_t)(h / 4) * w;
        for (uint32_t y = 0; y < band; y++) {
            for (uint32_t x = 0; x < w; x++) {
                p[y * w + x] = (x >= bar && x < bar + 24) ? 0xFFFFFF : 0x202020;
            }
        }
        if (bunix_fb_write((uint64_t)(h / 4) * w * 4, p, bandbytes)
                != (ssize_t)bandbytes) {
            wrong("writing the bar band");
        }
        bunix_sleepms(33);
    }

    // Keys: six seconds of them. Each edge lights a block in the strip along
    // the bottom, one column per scancode, and is echoed to the console.
    const uint32_t strip = 48;
    const uint32_t y0 = h - strip;
    const uint32_t bw = w / 0x80 ? w / 0x80 : 1;
    const size_t stripbytes = (size_t)strip * w * 4;
    long events = 0;
    uint64_t until = bunix_millis() + 6000;
    while (bunix_millis() < until) {
        uint64_t ev;
        if (!bunix_kbd_event(&ev)) {
            bunix_yield();
            continue;
        }
        events++;
        uint32_t code = (uint32_t)(ev & 0x7F);
        int up = (ev & BUNIX_KEY_UP) != 0;
        uint32_t *p = frame + (size_t)y0 * w;
        for (uint32_t y = 0; y < strip; y++) {
            for (uint32_t x = 0; x + 1 < bw; x++) {
                p[y * w + code * bw + x] = up ? 0x802020 : 0x20C020;
            }
        }
        if (bunix_fb_write((uint64_t)y0 * w * 4, p, stripbytes)
                != (ssize_t)stripbytes) {
            wrong("writing the key strip");
        }
        printf("fbtest: key 0x%x %s%s\n", code, up ? "up" : "down",
               (ev & BUNIX_KEY_EXT) ? " ext" : "");
    }
    printf("fbtest: %ld key events\n", events);

    // Put the screen back as it was found.
    if (bunix_fb_write(0, saved, bytes) != (ssize_t)bytes) {
        wrong("restoring the screen");
    }
    free(saved);
    free(frame);

    if (fails) {
        printf("fbtest: %d FAILURES\n", fails);
        return 1;
    }
    printf("fbtest: all ok\n");
    return 0;
}
