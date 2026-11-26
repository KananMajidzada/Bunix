use rt;

// The framebuffer as a user program sees it: a shadow buffer in the process's
// own memory, copied to /dev/fb when a frame is ready. This is the drawing
// layer the window manager needs; it is the same picture as the kernel's fb,
// but none of it lives in the kernel.

export def CW: size = 12;
export def CH: size = 16;
export def BLACK: u32 = 0x000000;
export def WHITE: u32 = 0xFFFFFF;

let shadow: uintptr = 0;
let pitch: size = 0;
let fbw: size = 0;
let fbh: size = 0;

export fn active() bool = shadow != 0;
export fn width() size = fbw;
export fn height() size = fbh;

export fn init() void = {
	let buf: [32]u8 = [0...];
	const n = rt::readfile("/proc/fb", buf[..]);
	let w = 0z;
	let h = 0z;
	let at = 0z;
	for (at < n && (buf[at] == (' ': u8) || buf[at] == ('\n': u8))) {
		at += 1;
	};
	for (at < n && buf[at] >= ('0': u8) && buf[at] <= ('9': u8)) {
		w = (w * 10) + (buf[at] - ('0': u8)): size;
		at += 1;
	};
	for (at < n && (buf[at] == (' ': u8) || buf[at] == ('\n': u8))) {
		at += 1;
	};
	for (at < n && buf[at] >= ('0': u8) && buf[at] <= ('9': u8)) {
		h = (h * 10) + (buf[at] - ('0': u8)): size;
		at += 1;
	};
	if (w == 0 || h == 0) {
		return;
	};
	const bytes = w * h * 4;
	const pages = ((bytes + 4095z) / 4096z): u64;
	shadow = rt::page_alloc(pages);
	if (shadow == 0) {
		return;
	};
	for (let i = 0z; i < bytes; i += 1) {
		*((shadow + i): *u8) = 0;
	};
	fbw = w;
	fbh = h;
	pitch = w * 4;
};

fn px(x: size, y: size, c: u32) void = {
	if (x < fbw && y < fbh) {
		*((shadow + (y * pitch + x * 4): uintptr): *u32) = c;
	};
};

export fn set(x: size, y: size, c: u32) void = px(x, y, c);

export fn fill(x: size, y: size, w: size, h: size, c: u32) void = {
	if (x >= fbw || y >= fbh) {
		return;
	};
	let ww = w;
	let hh = h;
	if (x + ww > fbw) {
		ww = fbw - x;
	};
	if (y + hh > fbh) {
		hh = fbh - y;
	};
	for (let j = 0z; j < hh; j += 1) {
		for (let i = 0z; i < ww; i += 1) {
			px(x + i, y + j, c);
		};
	};
};

export fn blit(x: size, y: size, w: size, h: size, src: uintptr, spitch: size) void = {
	if (shadow == 0 || w == 0 || h == 0 || x >= fbw || y >= fbh) {
		return;
	};
	let ww = w;
	let hh = h;
	if (x + ww > fbw) {
		ww = fbw - x;
	};
	if (y + hh > fbh) {
		hh = fbh - y;
	};
	for (let j = 0z; j < hh; j += 1) {
		const d = (shadow + ((y + j) * pitch + x * 4): uintptr): *opaque;
		const s = (src + ((j * spitch): uintptr)): *opaque;
		rt::memcpy(d, s, ww * 4);
	};
};

export fn cell(x: size, y: size, ch: u8, fg: u32, bg: u32) void = {
	fill(x, y, CW, CH, bg);
	let c = ch;
	if (c < ' ': u8 || c > 0x7E) {
		c = '?': u8;
	};
	const g = FONT[(c - ' ': u8): size];
	for (let column = 0z; column < 5; column += 1) {
		for (let row = 0z; row < 7; row += 1) {
			if (((g[column] >> row) & 1) != 0) {
				fill(x + 1 + column * 2, y + 1 + row * 2, 2, 2, fg);
			};
		};
	};
};

export fn text(x: size, y: size, s: str, fg: u32, bg: u32) void = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b); i += 1) {
		cell(x + i * CW, y, b[i], fg, bg);
	};
};

type raw = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

// A slice view of memory the window manager owns. The syscall copies it
// before returning, so one shared header is enough.
let rawbuf = raw { data = 0, length = 0, capacity = 0 };
fn bytes(p: uintptr, n: size) []u8 = {
	rawbuf.data = p;
	rawbuf.length = n;
	rawbuf.capacity = n;
	return *(&rawbuf: *[]u8);
};

export fn present() void = {
	if (shadow == 0) {
		return;
	};
	_ = rt::writeat("/dev/fb", bytes(shadow, pitch * fbh), 0);
};

export fn present_rect(x: size, y: size, w: size, h: size) void = {
	if (shadow == 0 || x >= fbw || y >= fbh) {
		return;
	};
	let ww = w;
	let hh = h;
	if (x + ww > fbw) {
		ww = fbw - x;
	};
	if (y + hh > fbh) {
		hh = fbh - y;
	};
	for (let j = 0z; j < hh; j += 1) {
		const at = (y + j) * pitch + x * 4;
		_ = rt::writeat("/dev/fb", bytes(shadow + at, ww * 4), at: u64);
	};
};
