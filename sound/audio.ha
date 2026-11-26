use architecture;
use sched;

// Audio as a file.
//
// /dev/audio is the machine's speaker to a program: writing PCM to it
// plays the PCM. /dev/audioctl says and sets the format, and /proc/audio
// says what card was found. Any program that can write a file can make a
// sound, with no library and no system call of its own, which is the
// point: a game that draws to /dev/fb reads keys from /dev/kbd and already
// writes its frames to a file now writes its samples to one too.
//
// The samples are queued in a ring and handed to the card a block at a
// time. A write blocks only while the ring is full, so a program that
// makes a small sound every frame is not held up by the length of the
// sound. The block that finishes raises the card's interrupt; the handler
// starts the next one, and that is what keeps the sound going between the
// program's writes.
//
// The card's DMA engine can only reach the first 16 MiB of memory. The
// kernel is linked at 64 MiB, so the buffer is not in the kernel's own
// image: it is the conventional 1 MiB page, which mem::init has already
// reserved along with the rest of the space below the kernel. Nothing else
// asks for it, and it is 64 KiB aligned so a block can never straddle a
// boundary the old DMA controller cannot cross.

def FIFO_SZ: size = 32768;
def CHUNK: size = 16384;
def DMA_BUF: uintptr = 0x00100000;
def DEFAULT_RATE: u32 = 44100;
def DEFAULT_CHANNELS: u8 = 2;
def DEFAULT_BITS: u8 = 16;

let fifo: [FIFO_SZ]u8 = [0...];
let fhead: size = 0;
let ftail: size = 0;
let fcount: size = 0;

let rate: u32 = DEFAULT_RATE;
let channels: u8 = DEFAULT_CHANNELS;
let bits: u8 = DEFAULT_BITS;
// System volume, in percent. It applies to every program and survives a
// format change: it is a setting of the machine, not of one tune.
let volume: u8 = 100;

let active: bool = false;
let owner: size = sched::NOID;
let blocks: u64 = 0;
let irqs: u64 = 0;

export fn audio_present() bool = present();
export fn audio_irq_line() u8 = irq();

fn frame_size() size = {
	let f = if (bits == 16) 2z else 1z;
	if (channels == 2) {
		f = f * 2;
	};
	return f;
};

fn fifo_put(data: []u8, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		fifo[ftail] = data[i];
		ftail = (ftail + 1) % FIFO_SZ;
	};
	fcount += n;
};

// The machine's volume, applied to the copy that goes to the card. The
// ring keeps the original samples, so changing the volume takes effect on
// the next block without touching what is already queued.
fn apply_volume(n: size) void = {
	if (volume == 100) {
		return;
	};
	const per = if (channels == 2) 2z else 1z;
	if (bits == 16) {
		const frames = n / (per * 2);
		for (let i = 0z; i < frames; i += 1) {
			for (let c = 0z; c < per; c += 1) {
				const at = DMA_BUF + ((i * per) + c) * 2;
				const p = (at: *i16);
				const v = (*p: i64) * (volume: i64) / 100;
				*p = v: i16;
			};
		};
	} else {
		for (let i = 0z; i < n; i += 1) {
			const p = ((DMA_BUF + i): *u8);
			const v = ((*p: i64) - 128) * (volume: i64) / 100;
			*p = (v + 128): u8;
		};
	};
};

// Moves the oldest n bytes of the ring into the card's buffer. They are
// consumed either way; the card reads the buffer without the kernel's
// help, so nothing may touch it until the interrupt says the block is
// over.
fn fifo_take(n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		*((DMA_BUF + i): *u8) = fifo[fhead];
		fhead = (fhead + 1) % FIFO_SZ;
	};
	fcount -= n;
	apply_volume(n);
};

fn kick() void = {
	if (active || fcount == 0) {
		return;
	};
	const frame = frame_size();
	let n = if (fcount > CHUNK) CHUNK else fcount;
	n = (n / frame) * frame;
	if (n == 0) {
		return;
	};
	fifo_take(n);
	active = play(DMA_BUF, n, rate, channels, bits);
	if (active) {
		blocks += 1;
	};
};

export fn audio_init() void = {
	if (!init()) {
		return;
	};
	rate = DEFAULT_RATE;
	channels = DEFAULT_CHANNELS;
	bits = DEFAULT_BITS;
};

// The card's interrupt: the block just ended, so the next one can start.
// The handler runs with interrupts already off, which is what the ring
// wants.
export fn audio_irq(vec: u64) void = {
	if (!present()) {
		return;
	};
	const line = irq();
	const want = if (line < 8) (32: u64) + (line: u64) else (40: u64) + ((line: u64) - 8);
	if (vec != want) {
		return;
	};
	ack();
	irqs += 1;
	if (!active) {
		return;
	};
	active = false;
	kick();
};

export fn audio_stop() void = {
	stop();
	active = false;
	fhead = 0;
	ftail = 0;
	fcount = 0;
	owner = sched::NOID;
};

// A process that leaves has no sound to finish: its samples were written
// for this moment, and playing them in an empty desktop is only noise.
export fn audio_release(id: size) void = {
	if (owner == id) {
		audio_stop();
	};
};

export fn audio_write(data: []u8, off: u64) size = {
	_ = off;
	if (!present()) {
		return 0;
	};
	const me = sched::current_id();
	if (owner != me) {
		audio_stop();
		owner = me;
	};
	let sent = 0z;
	let stalled = 0u64;
	for (sent < len(data)) {
		architecture::cli();
		if (fcount < FIFO_SZ) {
			const room = FIFO_SZ - fcount;
			let n = len(data) - sent;
			if (n > room) {
				n = room;
			};
			fifo_put(data[sent..], n);
			sent += n;
			kick();
			architecture::sti();
			stalled = 0;
			continue;
		};
		// The ring is full and the card is the only one that can empty
		// it. Let the clock run so the interrupt can arrive and so the
		// machine can do something else while this program waits. A
		// pause instruction would only spin: it is a hint to the
		// processor, not a wait. Watching the clock is what the speaker
		// does for a note, and it lets the scheduler take this thread
		// away between ticks.
		architecture::sti();
		const until = architecture::millis() + 1;
		for (architecture::millis() < until) void;
		stalled += 1;
		if (stalled > 1000) {
			// Ten seconds without the card coming back. Keeping the
			// caller here forever would hang it for a fault on
			// hardware it cannot see.
			architecture::cli();
			return sent;
		};
	};
	architecture::cli();
	return sent;
};

// A number written into buf, in decimal, at most room bytes of it.
fn put_num(buf: []u8, room: size, v: u64) size = {
	let tmp: [20]u8 = [0...];
	let k = len(tmp);
	if (v == 0) {
		k -= 1;
		tmp[k] = ('0': u8);
	} else {
		let n = v;
		for (n > 0) {
			k -= 1;
			tmp[k] = ('0': u8) + (n % 10): u8;
			n /= 10;
		};
	};
	let out = 0z;
	for (let i = k; i < len(tmp) && out < room; i += 1) {
		buf[out] = tmp[i];
		out += 1;
	};
	return out;
};

fn put_str(buf: []u8, room: size, s: str) size = {
	const b = *(&s: *[]u8);
	let out = 0z;
	for (let i = 0z; i < len(b) && out < room; i += 1) {
		buf[out] = b[i];
		out += 1;
	};
	return out;
};

// /dev/audioctl reads back the format the card is set to.
export fn audioctl_read(buf: []u8, off: u64, n: size) size = {
	_ = off;
	if (!present() || len(buf) == 0) {
		return 0;
	};
	let room = n;
	if (room > len(buf)) {
		room = len(buf);
	};
	let k = put_num(buf, room, rate: u64);
	if (k < room) {
		buf[k] = (' ': u8);
		k += 1;
	};
	k += put_num(buf[k..], room - k, channels: u64);
	if (k < room) {
		buf[k] = (' ': u8);
		k += 1;
	};
	k += put_num(buf[k..], room - k, bits: u64);
	if (k < room) {
		buf[k] = (' ': u8);
		k += 1;
	};
	k += put_num(buf[k..], room - k, volume: u64);
	if (k < room) {
		buf[k] = ('\n': u8);
		k += 1;
	};
	return k;
};

fn number(s: []u8, at: *size, v: *u64) bool = {
	let i = *at;
	for (i < len(s) && (s[i] == (' ': u8) || s[i] == ('\n': u8)
			|| s[i] == ('\t': u8) || s[i] == ('\r': u8))) {
		i += 1;
	};
	const start = i;
	for (i < len(s) && s[i] >= ('0': u8) && s[i] <= ('9': u8)) {
		i += 1;
	};
	if (i == start) {
		return false;
	};
	let acc = 0u64;
	for (let j = start; j < i; j += 1) {
		if (acc < 100000000) {
			acc = (acc * 10) + (s[j] - ('0': u8)): u64;
		};
	};
	*at = i;
	*v = acc;
	return true;
};

// A word at the start of a control line, after any space. The position is
// left just past it, so a number may be read next.
fn match_word(s: []u8, at: *size, word: []u8) bool = {
	let i = *at;
	for (i < len(s) && (s[i] == (' ': u8) || s[i] == ('\n': u8)
			|| s[i] == ('\t': u8) || s[i] == ('\r': u8))) {
		i += 1;
	};
	if (i + len(word) > len(s)) {
		return false;
	};
	for (let j = 0z; j < len(word); j += 1) {
		if (s[i + j] != word[j]) {
			return false;
		};
	};
	*at = i + len(word);
	return true;
};

fn is_stop(s: []u8) bool = {
	const word: [4]u8 = ['s', 't', 'o', 'p'];
	let i = 0z;
	return match_word(s, &i, word[..]);
};

// /dev/audioctl takes "rate channels bits", or "stop". A format change
// stops the card first, so a block in the old format is not heard as the
// new one.
export fn audioctl_write(data: []u8, off: u64) size = {
	_ = off;
	if (!present()) {
		return 0;
	};
	if (is_stop(data)) {
		audio_stop();
		return len(data);
	};
	// "volume N" sets the machine's volume, from zero to a hundred. It
	// does not stop the card: a tune playing at the old level simply
	// continues at the new one from the next block on.
	const word: [6]u8 = ['v', 'o', 'l', 'u', 'm', 'e'];
	let vi = 0z;
	let v = 0u64;
	if (match_word(data, &vi, word[..]) && number(data, &vi, &v)) {
		if (v > 100) {
			return 0;
		};
		volume = v: u8;
		return len(data);
	};
	let i = 0z;
	let r = 0u64;
	let c = 0u64;
	let b = 0u64;
	if (!number(data, &i, &r) || !number(data, &i, &c) || !number(data, &i, &b)) {
		return 0;
	};
	if (r < 5000 || r > 45000 || (c != 1 && c != 2) || (b != 8 && b != 16)) {
		return 0;
	};
	audio_stop();
	rate = r: u32;
	channels = c: u8;
	bits = b: u8;
	return len(data);
};

// /proc/audio: what the machine has, in words a person can read.
export fn audio_status(buf: []u8) size = {
	if (!present()) {
		return put_str(buf, len(buf), "none\n");
	};
	let k = put_str(buf, len(buf), "sb16 base ");
	k += put_num(buf[k..], len(buf) - k, (base_port(): u64));
	k += put_str(buf[k..], len(buf) - k, " irq ");
	k += put_num(buf[k..], len(buf) - k, (irq(): u64));
	k += put_str(buf[k..], len(buf) - k, " dma ");
	k += put_num(buf[k..], len(buf) - k, (dma8(): u64));
	k += put_str(buf[k..], len(buf) - k, " ");
	k += put_num(buf[k..], len(buf) - k, (dma16(): u64));
	k += put_str(buf[k..], len(buf) - k, " blocks ");
	k += put_num(buf[k..], len(buf) - k, blocks);
	k += put_str(buf[k..], len(buf) - k, " irqs ");
	k += put_num(buf[k..], len(buf) - k, irqs);
	k += put_str(buf[k..], len(buf) - k, " queued ");
	k += put_num(buf[k..], len(buf) - k, fcount: u64);
	k += put_str(buf[k..], len(buf) - k, " volume ");
	k += put_num(buf[k..], len(buf) - k, volume: u64);
	k += put_str(buf[k..], len(buf) - k, "\n");
	return k;
};
