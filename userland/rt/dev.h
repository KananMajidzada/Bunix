// dev.h - the device files a program that draws rather than types uses.
//
// Bunix keeps everything in files, and the hardware a drawing program wants is
// no exception. The screen is /dev/fb: 32-bit pixels packed tightly, width by
// height, row after row with no padding, so a frame is one run of width*height*
// 4 bytes and the card's own stride never crosses the boundary. The keyboard is
// /dev/kbd: key edges as 64-bit words, the scancode low, BUNIX_KEY_UP when a
// key was released and BUNIX_KEY_EXT when the scancode was an extended one. A
// game holds several keys at once and has to see the moment one is let go,
// which a character stream cannot tell it. The clock is /proc/millis:
// milliseconds since boot, so a game loop paces itself against the machine
// rather than counting its own iterations. The screen's size is /proc/fb.
//
// Everything here rides the read and write syscalls already there; no system
// call of its own is needed.

#ifndef BUNIX_DEV_H
#define BUNIX_DEV_H

#include <stddef.h>
#include <stdint.h>
#include "syscalls.h"

// One key edge, as /dev/kbd packs it into a 64-bit word.
#define BUNIX_KEY_UP  0x100  // the key was released rather than pressed
#define BUNIX_KEY_EXT 0x200  // an extended scancode: arrows, right Ctrl/Alt

// The pointer as a file: movement and button state as 64-bit words, one per
// event. Movement is in the low 16 bits and the next, both signed, and the
// buttons are at byte 4 with bit 0 left, 1 right, 2 middle. A game polls this
// between frames; no event is waiting when the pointer has not moved.
static inline int bunix_mouse_event(uint64_t *ev) {
    return bunix_readfile("/dev/mouse", ev, sizeof(*ev)) == (ssize_t)sizeof(*ev);
}

// The size of the picture the program draws into, read from /dev/win. It
// changes when the window is resized or filled with the screen, so a program
// can lay out a frame that fits however large the window has become.
static inline int bunix_win_dims(uint32_t *w, uint32_t *h) {
    char buf[32];
    ssize_t n = bunix_readfile("/dev/win", buf, sizeof(buf) - 1);
    if (n <= 0) return -1;
    buf[n] = 0;
    uint32_t a = 0, b = 0;
    const char *p = buf;
    while (*p >= '0' && *p <= '9') a = a * 10 + (uint32_t)(*p++ - '0');
    while (*p == ' ') p++;
    while (*p >= '0' && *p <= '9') b = b * 10 + (uint32_t)(*p++ - '0');
    if (a == 0 || b == 0) return -1;
    *w = a;
    *h = b;
    return 0;
}

// A drawing window of one's own, as /dev/win offers it: writing the program's
// name asks for one, and reading it back gives the size of the picture the
// program draws into, as "width height". With a window the program's writes to
// /dev/fb land in the window rather than on the screen, so the desktop and the
// program share the display. Fails when there is no desktop - a serial-only
// boot - and then the program has the screen to itself.
static inline int bunix_win_open(const char *name, uint32_t *w, uint32_t *h) {
    if (bunix_writeat("/dev/win", 0, name, path_len(name)) <= 0) return -1;
    return bunix_win_dims(w, h);
}

// Fills the screen with the drawing window, or puts it back where it was.
// '1' is fullscreen, '0' is the window again, and any other byte switches
// between the two - which is what the square on the title bar does, so the
// two ways of asking always agree. Fails without a window of one's own.
static inline int bunix_win_full(char mode) {
    return bunix_writeat("/dev/win", 1, &mode, 1) == 1 ? 0 : -1;
}

// The screen's size in pixels, read from /proc/fb. Returns 0 on success and
// -1 when there is no framebuffer, which is what a serial-only boot has.
static inline int bunix_fb_dims(uint32_t *w, uint32_t *h) {
    char buf[32];
    ssize_t n = bunix_readfile("/proc/fb", buf, sizeof(buf) - 1);
    if (n <= 0) return -1;
    buf[n] = 0;
    uint32_t a = 0, b = 0;
    const char *p = buf;
    while (*p >= '0' && *p <= '9') a = a * 10 + (uint32_t)(*p++ - '0');
    while (*p == ' ') p++;
    while (*p >= '0' && *p <= '9') b = b * 10 + (uint32_t)(*p++ - '0');
    if (a == 0 || b == 0) return -1;
    *w = a;
    *h = b;
    return 0;
}

// Draws pixels: off is a byte offset into the screen's file, so writing at 0
// is a whole frame and writing at row*stride is the band below it. What is
// written shows once the call returns; a frame is never seen half-painted.
static inline ssize_t bunix_fb_write(uint64_t off, const void *px, size_t bytes) {
    return bunix_writeat("/dev/fb", off, px, bytes);
}

// Takes pixels back off the screen, packed the same way. A program that wants
// to put the screen back as it found it saves it first with this.
static inline ssize_t bunix_fb_read(uint64_t off, void *px, size_t bytes) {
    return bunix_readat("/dev/fb", off, px, bytes);
}

// The next key edge, or 0 when none is waiting. A game polls this between
// frames rather than blocking on it.
static inline int bunix_kbd_event(uint64_t *ev) {
    return bunix_readfile("/dev/kbd", ev, sizeof(*ev)) == (ssize_t)sizeof(*ev);
}

// Milliseconds since boot, from /proc/millis.
static inline uint64_t bunix_millis(void) {
    char buf[24];
    ssize_t n = bunix_readfile("/proc/millis", buf, sizeof(buf) - 1);
    if (n <= 0) return 0;
    buf[n] = 0;
    uint64_t v = 0;
    for (const char *p = buf; *p >= '0' && *p <= '9'; p++) {
        v = v * 10 + (uint64_t)(*p - '0');
    }
    return v;
}

// Waits for ms to pass, giving the processor to other programs meanwhile.
// There is no sleep system call; the clock file is read again and again until
// the time is up, yielding between reads.
static inline void bunix_sleepms(uint64_t ms) {
    uint64_t until = bunix_millis() + ms;
    while (bunix_millis() < until) {
        bunix_yield();
    }
}

#endif
