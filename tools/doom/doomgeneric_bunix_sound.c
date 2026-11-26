// Doom's sound on Bunix.
//
// Every program on this machine reaches the sound card by writing samples to
// /dev/audio, and so does the game. This file is Doom's own mixer: it turns the
// eight-bit mono effects the WAD holds into sixteen-bit stereo at the card's
// rate, keeps up to sixteen of them playing at once, and writes the mixed
// result to the file. It has no port, interrupt or mixer register of its own -
// those belong to the kernel, where they are shared by every program.
//
// Samples are generated against the same clock the game runs on. The game
// calls Update every time through its loop; this asks how much time has gone
// by and mixes just that much sound, so a shot heard in the game is heard at
// the same moment on the card and the game never runs ahead of its own audio.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <dev.h>

#include "config.h"
#include "deh_str.h"
#include "doomtype.h"
#include "i_sound.h"
#include "m_misc.h"
#include "w_wad.h"
#include "z_zone.h"
#include "doomgeneric.h"

#define OUT_RATE 44100
#define OUT_CHANNELS 2
#define OUT_BITS 16
#define NUM_CHANNELS 16

// Never write less than eight milliseconds at a time, or the game would be
// making a system call every pass through its loop. Never write more than
// fifty, so that a pause to load a level cannot pour half a second of stale
// sound into the card when play resumes.
#define MIN_SLICE_MS 8
#define MAX_SLICE_MS 50
#define MIX_FRAMES ((OUT_RATE * MAX_SLICE_MS) / 1000)

static int16_t mixbuf[MIX_FRAMES * OUT_CHANNELS];

// An effect after conversion: sixteen-bit stereo at the card's own rate.
typedef struct {
    int16_t *data;
    int frames;
} bunix_sfx_t;

typedef struct {
    const int16_t *data;
    int frames;
    int pos;
    int vol;   // 0..127
    int sep;   // 0..254
    boolean playing;
} channel_t;

static channel_t channels[NUM_CHANNELS];
static boolean sound_initialized = false;
static boolean use_sfx_prefix = true;
static uint32_t last_ms;

// These belong to the sound variables i_sound.c binds when sound is part of
// the build. Nothing on this machine resamples through libsamplerate - the
// conversion below is done once when a lump is cached - but the variables
// still have to exist.
int use_libsamplerate = 0;
float libsamplerate_scale = 0.65f;

// One sound effect, converted once and kept in the effect's driver_data.
static boolean CacheSFX(sfxinfo_t *sfxinfo) {
    const int lump = sfxinfo->lumpnum;
    if (lump < 0) {
        return false;
    };
    byte *lumpdata = W_CacheLumpNum(lump, PU_STATIC);
    const int lumplen = W_LumpLength(lump);

    // A DMX effect: two bytes of marker, the sample rate, the sample count,
    // and then the eight-bit unsigned mono samples. The first and last
    // sixteen bytes are padding, which is why the count loses thirty-two.
    if (lumplen < 8 || lumpdata[0] != 0x03 || lumpdata[1] != 0x00) {
        W_ReleaseLumpNum(lump);
        return false;
    };
    const int samplerate = (lumpdata[3] << 8) | lumpdata[2];
    int length = (lumpdata[7] << 24) | (lumpdata[6] << 16)
               | (lumpdata[5] << 8) | lumpdata[4];
    if (samplerate <= 0 || length <= 48 || length > lumplen - 8) {
        W_ReleaseLumpNum(lump);
        return false;
    };
    const byte *src = lumpdata + 24;
    length -= 32;
    if (length <= 0) {
        W_ReleaseLumpNum(lump);
        return false;
    };

    const int outframes = (int)(((int64_t)length * OUT_RATE) / samplerate);
    if (outframes <= 0) {
        W_ReleaseLumpNum(lump);
        return false;
    };

    bunix_sfx_t *snd = malloc(sizeof(*snd) + (size_t)outframes * 4);
    if (snd == NULL) {
        W_ReleaseLumpNum(lump);
        return false;
    };
    snd->data = (int16_t *)(snd + 1);
    snd->frames = outframes;

    // Nearest-neighbour resampling in fixed point, the way the other ports
    // do it when there is no samplerate library. The source index advances
    // in 1/256ths of an output frame, so the pitch stays even.
    const int ratio = (length << 8) / outframes;
    for (int i = 0; i < outframes; i++) {
        int at = (i * ratio) >> 8;
        if (at >= length) {
            at = length - 1;
        };
        const int16_t v = (int16_t)(((int)src[at] - 128) << 8);
        snd->data[i * 2] = v;
        snd->data[i * 2 + 1] = v;
    };

    // The same one-pole filter the other ports use after stretching eight
    // bits to sixteen: it takes the harshness out of the repeated samples.
    // alpha = samplerate / (pi * OUT_RATE + samplerate), in 256ths.
    const int denom = ((314 * OUT_RATE) / 100) + samplerate;
    const int alpha = (samplerate * 256) / denom;
    if (alpha > 0 && alpha < 256) {
        for (int i = 2; i < outframes * 2; i++) {
            const int v = ((int)snd->data[i] * alpha)
                        + ((int)snd->data[i - 2] * (256 - alpha));
            snd->data[i] = (int16_t)(v >> 8);
        };
    };

    sfxinfo->driver_data = snd;
    W_ReleaseLumpNum(lump);
    return true;
}

static void GetSfxLumpName(sfxinfo_t *sfx, char *buf, size_t len) {
    if (sfx->link != NULL) {
        sfx = sfx->link;
    };
    if (use_sfx_prefix) {
        M_snprintf(buf, len, "ds%s", DEH_String(sfx->name));
    } else {
        M_StringCopy(buf, DEH_String(sfx->name), len);
    };
}

static int I_Bunix_GetSfxLumpNum(sfxinfo_t *sfx) {
    char namebuf[9];
    GetSfxLumpName(sfx, namebuf, sizeof(namebuf));
    return W_GetNumForName(namebuf);
}

static boolean I_Bunix_InitSound(boolean prefix) {
    if (bunix_audio_format(OUT_RATE, OUT_CHANNELS, OUT_BITS) != 0) {
        return false;
    };
    use_sfx_prefix = prefix;
    memset(channels, 0, sizeof(channels));
    last_ms = DG_GetTicksMs();
    sound_initialized = true;
    return true;
}

static void I_Bunix_ShutdownSound(void) {
    if (!sound_initialized) {
        return;
    };
    bunix_audio_stop();
    sound_initialized = false;
}

static void I_Bunix_UpdateSoundParams(int channel, int vol, int sep) {
    if (!sound_initialized || channel < 0 || channel >= NUM_CHANNELS) {
        return;
    };
    channels[channel].vol = vol;
    channels[channel].sep = sep;
}

static int I_Bunix_StartSound(sfxinfo_t *sfxinfo, int channel, int vol, int sep) {
    if (!sound_initialized || channel < 0 || channel >= NUM_CHANNELS) {
        return -1;
    };
    if (sfxinfo->driver_data == NULL && !CacheSFX(sfxinfo)) {
        return -1;
    };
    bunix_sfx_t *snd = sfxinfo->driver_data;
    channels[channel].data = snd->data;
    channels[channel].frames = snd->frames;
    channels[channel].pos = 0;
    channels[channel].vol = vol;
    channels[channel].sep = sep;
    channels[channel].playing = true;
    return channel;
}

static void I_Bunix_StopSound(int channel) {
    if (!sound_initialized || channel < 0 || channel >= NUM_CHANNELS) {
        return;
    };
    channels[channel].playing = false;
    channels[channel].data = NULL;
}

static boolean I_Bunix_SoundIsPlaying(int channel) {
    if (!sound_initialized || channel < 0 || channel >= NUM_CHANNELS) {
        return false;
    };
    const channel_t *c = &channels[channel];
    return c->playing && c->data != NULL && c->pos < c->frames;
}

static void I_Bunix_UpdateSound(void) {
    if (!sound_initialized) {
        return;
    };

    // The game calls this on every pass through its loop, often two or more
    // times within one millisecond. Wait until enough time has passed to be
    // worth a write, and make exactly the amount of sound that has elapsed.
    const uint32_t now = DG_GetTicksMs();
    uint32_t elapsed = now - last_ms;
    if (elapsed < MIN_SLICE_MS) {
        return;
    };
    if (elapsed > MAX_SLICE_MS) {
        elapsed = MAX_SLICE_MS;
    };
    last_ms = now;
    const int frames = (int)((elapsed * OUT_RATE) / 1000);

    memset(mixbuf, 0, (size_t)frames * OUT_CHANNELS * sizeof(int16_t));

    for (int ch = 0; ch < NUM_CHANNELS; ch++) {
        channel_t *c = &channels[ch];
        if (!c->playing || c->data == NULL) {
            continue;
        };
        // Doom gives a channel a volume from zero to 127 and a separation
        // from zero to 254. The same law the other ports use spreads those
        // across the two speakers while keeping a centre sound from being
        // twice as loud as a side one.
        int left = ((254 - c->sep) * c->vol) / 127;
        int right = (c->sep * c->vol) / 127;
        if (left > 254) left = 254;
        if (right > 254) right = 254;

        int i = 0;
        for (; i < frames && c->pos < c->frames; i++, c->pos++) {
            int32_t l = mixbuf[i * 2]
                      + (((int32_t)c->data[c->pos * 2] * left) / 254);
            int32_t r = mixbuf[i * 2 + 1]
                      + (((int32_t)c->data[c->pos * 2 + 1] * right) / 254);
            if (l < -32768) l = -32768;
            if (l > 32767) l = 32767;
            if (r < -32768) r = -32768;
            if (r > 32767) r = 32767;
            mixbuf[i * 2] = (int16_t)l;
            mixbuf[i * 2 + 1] = (int16_t)r;
        };
        if (c->pos >= c->frames) {
            c->playing = false;
            c->data = NULL;
        };
    };

    bunix_audio_write(mixbuf, (size_t)frames * OUT_CHANNELS * sizeof(int16_t));
}

static snddevice_t sound_bunix_devices[] = {
    SNDDEVICE_SB,
    SNDDEVICE_WAVEBLASTER,
};

sound_module_t DG_sound_module = {
    sound_bunix_devices,
    arrlen(sound_bunix_devices),
    I_Bunix_InitSound,
    I_Bunix_ShutdownSound,
    I_Bunix_GetSfxLumpNum,
    I_Bunix_UpdateSound,
    I_Bunix_UpdateSoundParams,
    I_Bunix_StartSound,
    I_Bunix_StopSound,
    I_Bunix_SoundIsPlaying,
    NULL,  // sounds are converted when first heard, not all at startup
};

// Music is not part of this port yet: the notes in the WAD are MIDI for an
// OPL chip, not samples. i_sound.c expects a music module whenever sound is
// compiled in, so here is one that quietly does nothing. The effects still
// play, and adding music later means filling in this module rather than
// changing the game or the kernel.

static boolean I_Bunix_InitMusic(void) { return false; }
static void I_Bunix_ShutdownMusic(void) {}
static void I_Bunix_SetMusicVolume(int volume) { (void)volume; }
static void I_Bunix_PauseMusic(void) {}
static void I_Bunix_ResumeMusic(void) {}
static void *I_Bunix_RegisterSong(void *data, int len) {
    (void)data;
    (void)len;
    return NULL;
}
static void I_Bunix_UnRegisterSong(void *handle) { (void)handle; }
static void I_Bunix_PlaySong(void *handle, boolean looping) {
    (void)handle;
    (void)looping;
}
static void I_Bunix_StopSong(void) {}
static boolean I_Bunix_MusicIsPlaying(void) { return false; }

music_module_t DG_music_module = {
    NULL,
    0,
    I_Bunix_InitMusic,
    I_Bunix_ShutdownMusic,
    I_Bunix_SetMusicVolume,
    I_Bunix_PauseMusic,
    I_Bunix_ResumeMusic,
    I_Bunix_RegisterSong,
    I_Bunix_UnRegisterSong,
    I_Bunix_PlaySong,
    I_Bunix_StopSong,
    I_Bunix_MusicIsPlaying,
    NULL,  // no polling needed
};
