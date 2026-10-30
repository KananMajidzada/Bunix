// doomgeneric_bunix.c - DOOM on Bunix.
//
// Everything the game needs from the machine arrives as files, the same ones
// any program that draws rather than types uses: the screen is /dev/fb, the
// keyboard /dev/kbd, the pointer /dev/mouse, the clock /proc/millis, and the
// game's data file is /doom1.wad in the filesystem like any other file. Five
// functions tie the two together: the frame the game renders is put into the
// window, key edges are translated into DOOM's own codes, mouse movement
// becomes one event, and the clock paces the game.
//
// The game draws into a window of the desktop, asked for by writing its name
// to /dev/win, so the game and the desktop share the screen and neither
// leaves marks on the other. The square on the window's title bar fills the
// screen with it or puts it back; the game is told the picture's new size by
// reading /dev/win again and lays the frame out to fit. Without a desktop - a
// serial-only boot - the game has the screen to itself instead, saves it on
// the way in and puts it back on the way out.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dev.h>

#include "doomgeneric.h"
#include "doomkeys.h"
#include "d_event.h"

static uint32_t screen_w, screen_h;  // the picture the game draws into
static int windowed;                 // in a window, rather than at the screen
static uint32_t *frame;   // the scaled frame, one 32-bit pixel per picture pixel
static uint32_t *saved;   // what the screen showed when the game began
static uint16_t *rowmap;  // which source row each picture row shows
static uint16_t *colmap;  // which source column each picture column shows

static void restore_screen(void) {
    if (saved != NULL) {
        bunix_fb_write(0, saved, (size_t)screen_w * screen_h * 4);
    }
}

// Sizes the frame and the scale tables to the picture the game draws into,
// which is the window's own and can change under the game: the player can
// fill the screen with the window or drag it to another size.
static void size_picture(uint32_t w, uint32_t h) {
    const size_t bytes = (size_t)w * h * 4;
    frame = realloc(frame, bytes);
    rowmap = realloc(rowmap, (size_t)h * sizeof(uint16_t));
    colmap = realloc(colmap, (size_t)w * sizeof(uint16_t));
    if (frame == NULL || rowmap == NULL || colmap == NULL) {
        printf("doom: not enough memory for the picture\n");
        exit(1);
    }
    // The game renders 640x400; the picture is whatever the window reports.
    // Each picture pixel shows the nearest source pixel, worked out here.
    for (uint32_t y = 0; y < h; y++) {
        rowmap[y] = (uint16_t)((uint64_t)y * DOOMGENERIC_RESY / h);
    }
    for (uint32_t x = 0; x < w; x++) {
        colmap[x] = (uint16_t)((uint64_t)x * DOOMGENERIC_RESX / w);
    }
    screen_w = w;
    screen_h = h;
}

void DG_Init(void) {
    uint32_t w = 0, h = 0;
    if (bunix_win_open("doom", &w, &h) == 0) {
        // A window of the desktop: its picture is the game's screen, and the
        // desktop paints everything around it. Nothing of the screen needs
        // saving, because the game never draws outside the window.
        windowed = 1;
        size_picture(w, h);
        return;
    }
    // No desktop to give the game a window, so the screen is the game's. It
    // is saved on the way in and put back on the way out.
    if (bunix_fb_dims(&w, &h) != 0) {
        printf("doom: this machine has no framebuffer\n");
        exit(1);
    }
    size_picture(w, h);
    const size_t bytes = (size_t)w * h * 4;
    saved = malloc(bytes);
    if (saved == NULL) {
        printf("doom: not enough memory for the screen\n");
        exit(1);
    }
    bunix_fb_read(0, saved, bytes);
    atexit(restore_screen);
}

// The frame scaled onto the picture, written to /dev/fb in one call. The
// write lands in the window and the window's rows are copied onto the card
// before the call returns, so a frame is never seen in half.
void DG_DrawFrame(void) {
    if (windowed) {
        // The window can have been resized or filled with the screen since
        // the last frame, so its size is asked again and the frame laid out
        // to fit whatever it has become.
        uint32_t w = 0, h = 0;
        if (bunix_win_dims(&w, &h) == 0 && (w != screen_w || h != screen_h)) {
            size_picture(w, h);
        }
    }
    for (uint32_t y = 0; y < screen_h; y++) {
        const uint32_t *src =
            DG_ScreenBuffer + (size_t)rowmap[y] * DOOMGENERIC_RESX;
        uint32_t *dst = frame + (size_t)y * screen_w;
        for (uint32_t x = 0; x < screen_w; x++) {
            dst[x] = src[colmap[x]];
        }
    }
    bunix_fb_write(0, frame, (size_t)screen_w * screen_h * 4);
}

uint32_t DG_GetTicksMs(void) {
    return (uint32_t)bunix_millis();
}

void DG_SleepMs(uint32_t ms) {
    bunix_sleepms(ms);
}

void DG_SetWindowTitle(const char *title) {
    (void)title;  // the window is called "doom", whatever the game calls itself
}

// Key edges waiting to become game events. /dev/kbd hands over make and
// break as they happen; DOOM wants its own codes and a down or up flag, so
// the translation happens once here rather than in the game's own input.
#define KEYQ 64
static struct {
    uint8_t down;
    uint8_t key;
} keyq[KEYQ];
static int keyq_head, keyq_n;

// Set 1 scancodes, as /dev/kbd reports them, into DOOM's keys. Zero is a key
// the game has no use for.
static const unsigned char keymap[128] = {
    [0x01] = KEY_ESCAPE,
    [0x02] = '1', [0x03] = '2', [0x04] = '3', [0x05] = '4',
    [0x06] = '5', [0x07] = '6', [0x08] = '7', [0x09] = '8',
    [0x0A] = '9', [0x0B] = '0',
    [0x0C] = KEY_MINUS, [0x0D] = KEY_EQUALS,
    [0x0E] = KEY_BACKSPACE, [0x0F] = KEY_TAB,
    [0x10] = 'q', [0x11] = 'w', [0x12] = 'e', [0x13] = 'r',
    [0x14] = 't', [0x15] = 'y', [0x16] = 'u', [0x17] = 'i',
    [0x18] = 'o', [0x19] = 'p',
    [0x1C] = KEY_ENTER,
    [0x1D] = KEY_RCTRL,
    [0x1E] = 'a', [0x1F] = 's', [0x20] = 'd', [0x21] = 'f',
    [0x22] = 'g', [0x23] = 'h', [0x24] = 'j', [0x25] = 'k',
    [0x26] = 'l',
    [0x2A] = KEY_RSHIFT, [0x36] = KEY_RSHIFT,
    [0x2C] = 'z', [0x2D] = 'x', [0x2E] = 'c', [0x2F] = 'v',
    [0x30] = 'b', [0x31] = 'n', [0x32] = 'm',
    [0x38] = KEY_RALT, [0x39] = ' ',
    // The arrows arrive with the extended bit, but a keypad without one
    // means the same thing to a player who has no keypad.
    [0x48] = KEY_UPARROW, [0x4B] = KEY_LEFTARROW,
    [0x4D] = KEY_RIGHTARROW, [0x50] = KEY_DOWNARROW,
    [0x3B] = KEY_F1, [0x3C] = KEY_F2, [0x3D] = KEY_F3, [0x3E] = KEY_F4,
    [0x3F] = KEY_F5, [0x40] = KEY_F6, [0x41] = KEY_F7, [0x42] = KEY_F8,
    [0x43] = KEY_F9, [0x44] = KEY_F10, [0x57] = KEY_F11, [0x58] = KEY_F12,
};

static void drain_keys(void) {
    uint64_t ev;
    while (keyq_n < KEYQ && bunix_kbd_event(&ev)) {
        const unsigned char k = keymap[ev & 0x7F];
        if (k == 0) {
            continue;
        }
        keyq[(keyq_head + keyq_n) % KEYQ].down = (ev & BUNIX_KEY_UP) == 0;
        keyq[(keyq_head + keyq_n) % KEYQ].key = k;
        keyq_n += 1;
    }
}

// Everything the pointer did since the last time, waiting on /dev/mouse.
// Movement is folded into one sum so a quick hand is never lost between
// frames, and the buttons come as they are now rather than as edges.
static void pump_mouse(void) {
    static int mdx, mdy, mbtn, posted;
    uint64_t ev;
    int moved = 0;
    while (bunix_mouse_event(&ev)) {
        const int16_t dx = (int16_t)(ev & 0xFFFF);
        const int16_t dy = (int16_t)((ev >> 16) & 0xFFFF);
        mdx += dx;
        mdy += dy;
        mbtn = (int)((ev >> 32) & 0xFF);
        moved = 1;
    }
    if (!moved && mbtn == posted) {
        return;
    }
    // One event for the whole lot: the game keeps the movement of one tic by
    // overwriting what it recorded, so several events would leave only the
    // last one's worth. Up on the screen is down for the game.
    event_t e;
    e.type = ev_mouse;
    e.data1 = mbtn;
    e.data2 = mdx;
    e.data3 = -mdy;
    e.data4 = 0;
    D_PostEvent(&e);
    mdx = 0;
    mdy = 0;
    posted = mbtn;
}

// One queued event, or none. A game polls between frames, so an empty queue
// is answered with zero rather than waiting on the keyboard. The pointer is
// pumped here too, at the end of the key queue: one place that input enters
// the game from, whatever the device it came off.
int DG_GetKey(int *pressed, unsigned char *key) {
    if (keyq_n == 0) {
        drain_keys();
        if (keyq_n == 0) {
            pump_mouse();
            return 0;
        }
    }
    *pressed = keyq[keyq_head].down;
    *key = keyq[keyq_head].key;
    keyq_head = (keyq_head + 1) % KEYQ;
    keyq_n -= 1;
    return 1;
}

// The game, once its data file is pointed at. The shareware WAD is in the
// root of the filesystem; DOOM is told so unless the command line already
// says where it is.
int main(int argc, char **argv) {
    char *args[16];
    int n = 0;
    int have_iwad = 0;
    for (int i = 0; i < argc && n < 14; i++) {
        if (i > 0 && strcmp(argv[i - 1], "-iwad") == 0) {
            have_iwad = 1;
        }
        args[n++] = argv[i];
    }
    if (!have_iwad) {
        args[n++] = (char *)"-iwad";
        args[n++] = (char *)"/doom1.wad";
    }
    doomgeneric_Create(n, args);
    for (;;) {
        doomgeneric_Tick();
    }
}
