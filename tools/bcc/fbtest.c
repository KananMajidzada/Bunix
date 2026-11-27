// fbtest - the drawing program's device files, end to end.
//
// The screen's size comes from /proc/fb, pixels go either to a shared window
// surface or to /dev/fb, the clock paces the frames, and key edges arrive from
// /dev/kbd. A window is asked for through /dev/win like any other drawing
// program; when the compositor gives a surface the pixels are written straight
// into it and /dev/flip presents them. Without one the old /dev/fb path is used
// and the screen is saved first and put back at the end. Anything wrong prints
// WRONG:, so the serial log tells the whole story without needing the picture.
//
// The picture helps anyway: bands of color fill the drawing area, a white bar
// sweeps a dark band with the milliseconds, and every key edge lights a block
// along the bottom, green as it goes down and red as it comes up, one column
// per scancode.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <dev.h>

static int fails;
static int windowed;
static uint64_t surface;
static uint32_t *pixels;
static uint32_t *frame;
static uint32_t *saved;

static void wrong(const char *what) {
    printf("WRONG: fbtest %s\n", what);
    fails++;
}

// Hands a finished band to whoever is showing the picture. A mapped surface
// only needs its doorbell rung; the file path writes the bytes that changed.
static ssize_t show_pixels(size_t off, size_t bytes) {
    if (pixels != 0) {
        bunix_flip(surface);
        return (ssize_t)bytes;
    };
    return bunix_fb_write(off, (const uint8_t *)frame + off, bytes);
}

int main(void) {
    uint32_t fw = 0, fh = 0;
    if (bunix_fb_dims(&fw, &fh) != 0) {
        printf("fbtest: no framebuffer\n");
        return 1;
    }

    uint32_t w = 0, h = 0;
    if (bunix_win_map("fbtest", &w, &h, &pixels, &surface) == 0) {
        windowed = 1;
        printf("fbtest: window %ux%u surface %lu\n", w, h,
               (unsigned long)surface);
    } else {
        w = fw;
        h = fh;
    };
    printf("fbtest: drawing %ux%u\n", w, h);

    size_t bytes = (size_t)w * h * 4;
    if (pixels == 0) {
        frame = malloc(bytes);
        saved = malloc(bytes);
        if (!frame || !saved) {
            printf("WRONG: fbtest out of memory\n");
            return 1;
        };
        // What the screen shows now, to be put back at the end. Reading it
        // back uses the same file the drawing goes to.
        if (bunix_fb_read(0, saved, bytes) != (ssize_t)bytes) {
            wrong("saving the screen");
        };
    };
    uint32_t *pic = pixels != 0 ? pixels : frame;

    // Frame one: bands of color across the whole drawing area, written whole.
    for (uint32_t y = 0; y < h; y++) {
        uint32_t c = ((y * 255) / h) << 8;
        for (uint32_t x = 0; x < w; x++) {
            pic[y * w + x] = c | ((x * 255) / w);
        };
    };
    if (show_pixels(0, bytes) != (ssize_t)bytes) {
        wrong("writing frame one");
    };

    // The clock: sleep against /proc/millis, then sweep a bar whose position
    // is read from it. The bar's band is written at an offset, a band of rows
    // without touching the rest of the picture.
    uint64_t t0 = bunix_millis();
    bunix_sleepms(400);
    uint64_t t1 = bunix_millis();
    if (t1 - t0 < 350 || t1 - t0 > 3000) {
        wrong("the clock did not advance by about 400ms");
    };
    printf("fbtest: slept %ld ms\n", (long)(t1 - t0));

    for (int step = 0; step < 20; step++) {
        // A shared surface is the whole screen, so a resized window only
        // changes how much of it this program uses.
        if (pixels != 0) {
            uint32_t nw = w, nh = h;
            if (bunix_win_dims(&nw, &nh) == 0 && nw != 0 && nh != 0) {
                w = nw;
                h = nh;
            };
        };
        const uint32_t band = h / 2;
        const size_t bandbytes = (size_t)band * w * 4;
        uint32_t bar = (uint32_t)(((bunix_millis() - t0) / 10) % w);
        uint32_t *p = pic + (size_t)(h / 4) * w;
        for (uint32_t y = 0; y < band; y++) {
            for (uint32_t x = 0; x < w; x++) {
                p[y * w + x] = (x >= bar && x < bar + 24) ? 0xFFFFFF : 0x202020;
            };
        };
        if (show_pixels((size_t)(h / 4) * w * 4, bandbytes)
                != (ssize_t)bandbytes) {
            wrong("writing the bar band");
        };
        bunix_sleepms(33);
    };

    // Keys: six seconds of them. Each edge lights a block in the strip along
    // the bottom, one column per scancode, and is echoed to the console.
    const uint32_t strip = h < 48 ? h : 48;
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
        };
        events++;
        uint32_t code = (uint32_t)(ev & 0x7F);
        int up = (ev & BUNIX_KEY_UP) != 0;
        uint32_t *p = pic + (size_t)y0 * w;
        for (uint32_t y = 0; y < strip; y++) {
            for (uint32_t x = 0; x + 1 < bw; x++) {
                uint32_t cx = code * bw + x;
                if (cx < w) {
                    p[y * w + cx] = up ? 0x802020 : 0x20C020;
                };
            };
        };
        if (show_pixels((size_t)y0 * w * 4, stripbytes)
                != (ssize_t)stripbytes) {
            wrong("writing the key strip");
        };
        printf("fbtest: key 0x%x %s%s\n", code, up ? "up" : "down",
               (ev & BUNIX_KEY_EXT) ? " ext" : "");
    };
    printf("fbtest: %ld key events\n", events);

    // Put the screen back only when this program owned all of it.
    if (saved != 0) {
        if (bunix_fb_write(0, saved, bytes) != (ssize_t)bytes) {
            wrong("restoring the screen");
        };
        free(saved);
        free(frame);
    };

    if (fails) {
        printf("fbtest: %d FAILURES\n", fails);
        return 1;
    };
    printf("fbtest: all ok\n");
    return 0;
}
