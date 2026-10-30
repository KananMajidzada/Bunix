use architecture;
use boot;
use mem;
use paging;

// Linear 32-bit framebuffer handed to the kernel by the bootloader. Drawing
// lands in a RAM shadow; present copies it onto the card in one pass, so a
// frame never shows half a repaint and a moved window never leaves a trail.

export def CW: size = 12;
export def CH: size = 16;

export def BLACK: u32 = 0x000000;
export def WHITE: u32 = 0xFFFFFF;

let addr: uintptr = 0;		// where drawing goes (the shadow, once set up)
let real: uintptr = 0;		// the card's own memory
let shadow: uintptr = 0;
let pitch: size = 0;
let fbw: size = 0;
let fbh: size = 0;

export fn active() bool = {
	return addr != 0;
};

export fn width() size = fbw;
export fn height() size = fbh;

// Claims a shadow the size of the screen and points drawing at it.
fn shadow_init() void = {
	const bytes = pitch * fbh;
	const pages = (((bytes + 4095z) / 4096z): u64);
	const p = mem::frames_alloc(pages);
	if (p == 0) {
		return;
	};
	for (let i = 0z; i < bytes; i += 1) {
		*((p + i): *u8) = 0;
	};
	real = addr;
	shadow = p;
	addr = p;
};

export fn init(mb: *boot::info) void = {
	if ((mb.flags & boot::FLAG_VIDEO) == 0) {
		return;
	};
	if (mb.framebuffer_bpp != 32) {
		return;
	};
	addr = mb.framebuffer_addr: uintptr;
	pitch = mb.framebuffer_pitch: size;
	fbw = mb.framebuffer_width: size;
	fbh = mb.framebuffer_height: size;
	paging::map_fb(addr, (pitch * fbh): u64);
	shadow_init();
};

fn px(x: size, y: size, c: u32) void = {
	if (x < fbw && y < fbh) {
		*((addr + (y * pitch + x * 4): uintptr): *u32) = c;
	};
};

export fn set(x: size, y: size, c: u32) void = {
	px(x, y, c);
};

export fn get(x: size, y: size) u32 = {
	if (x < fbw && y < fbh) {
		return *((addr + (y * pitch + x * 4): uintptr): *u32);
	};
	return 0;
};

export fn fill(x: size, y: size, w: size, h: size, c: u32) void = {
	if (x >= fbw || y >= fbh) {
		return;
	};
	if (x + w > fbw) {
		w = fbw - x;
	};
	if (y + h > fbh) {
		h = fbh - y;
	};
	const pair = ((c: u64) << 32) | (c: u64);
	for (let j = 0z; j < h; j += 1) {
		let i = 0z;
		if ((x & 1z) != 0) {
			px(x, y + j, c);
			i = 1;
		};
		const words = (w - i) / 2z;
		if (words > 0) {
			const b = addr + ((y + j) * pitch + (x + i) * 4): uintptr;
			architecture::store64(b, pair, words);
		};
		if ((w - i) % 2z == 1) {
			px(x + w - 1, y + j, c);
		};
	};
};

// Copies the shadow onto the card. A full frame is one pass of 8-byte moves.
export fn present() void = {
	if (shadow == 0) {
		return;
	};
	architecture::memcpy(real, shadow, pitch * fbh);
};

export fn present_rect(x: size, y: size, w: size, h: size) void = {
	if (shadow == 0 || x >= fbw || y >= fbh) {
		return;
	};
	if (x + w > fbw) {
		w = fbw - x;
	};
	if (y + h > fbh) {
		h = fbh - y;
	};
	for (let j = 0z; j < h; j += 1) {
		const off = (y + j) * pitch + x * 4;
		architecture::memcpy(real + off, shadow + off, w * 4);
	};
};

// Copies a rectangle of tightly packed 32-bit pixels from a buffer the caller
// owns into the shadow, clipped to the screen. Nothing reaches the card, so a
// caller can lay a whole picture out and show it later in one present; the
// window manager uses it to repaint a drawing window from the copy it keeps
// of the program's last frame.
export fn blit(x: size, y: size, w: size, h: size, src: uintptr, spitch: size) void = {
	if (addr == 0 || w == 0 || h == 0 || x >= fbw || y >= fbh) {
		return;
	};
	if (x + w > fbw) {
		w = fbw - x;
	};
	if (y + h > fbh) {
		h = fbh - y;
	};
	for (let j = 0z; j < h; j += 1) {
		const d = addr + ((y + j) * pitch + x * 4): uintptr;
		architecture::memcpy(d, src + ((j * spitch): uintptr), w * 4);
	};
};

export fn cell(x: size, y: size, ch: u8, fg: u32, bg: u32) void = {
	fill(x, y, CW, CH, bg);
	if (ch < ' ': u8 || ch > 0x7E) {
		ch = '?': u8;
	};
	const g = FONT[(ch - ' ': u8): size];
	for (let c = 0z; c < 5; c += 1) {
		for (let r = 0z; r < 7; r += 1) {
			if (((g[c] >> r) & 1) != 0) {
				fill(x + 1 + c * 2, y + 1 + r * 2, 2, 2, fg);
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

export fn bigcell(x: size, y: size, ch: u8, sc: size, fg: u32, bg: u32) void = {
	fill(x, y, CW * sc, CH * sc, bg);
	if (ch < ' ': u8 || ch > 0x7E) {
		ch = '?': u8;
	};
	const g = FONT[(ch - ' ': u8): size];
	for (let c = 0z; c < 5; c += 1) {
		for (let r = 0z; r < 7; r += 1) {
			if (((g[c] >> r) & 1) != 0) {
				fill(x + sc + c * 2 * sc, y + sc + r * 2 * sc, sc, sc, fg);
			};
		};
	};
};

export fn text_big(x: size, y: size, s: str, sc: size, fg: u32, bg: u32) void = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b); i += 1) {
		bigcell(x + i * CW * sc, y, b[i], sc, fg, bg);
	};
};

// The framebuffer as a file, in the Plan 9 spirit: a program that draws gets
// at the display by writing /dev/fb, with no call of its own. The file is the
// screen as a flat, tightly packed block of 32-bit pixels, width * height * 4
// bytes, row after row with no padding. The hardware's own stride is an inner
// detail and never crosses the boundary, so a program lays out a frame as it
// pleases and does not have to know how the card happens to be addressed.
//
// A write lands in the shadow and then the rows it touched are copied onto the
// card, so a frame is never shown half-painted and a program that updates one
// band does not pay for the whole screen.

// The size in bytes of the framebuffer file: one 32-bit pixel per pixel.
export fn dev_size() u64 = {
	if (addr == 0) {
		return 0;
	};
	return (fbw * fbh * 4): u64;
};

// The screen the file describes, so a program can lay a frame out to fit.
export fn dev_dims(w: *size, h: *size) void = {
	*w = fbw;
	*h = fbh;
};

// Copies a run of pixels the caller owns onto the screen. The pixels are
// packed 32-bit, width w then height h, and sit at the byte offset off in the
// file, which names a pixel position by off / 4. Whole rows are moved in one
// pass; the ragged head and tail of a partial write go a pixel at a time.
export fn dev_write(data: []u8, off: u64) size = {
	const total = dev_size();
	if (total == 0 || off >= total || len(data) == 0) {
		return 0;
	};
	let n = (len(data): u64);
	if (off + n > total) {
		n = total - off;
	};
	// The pixel the write starts at, and the row and column it names.
	let p = (off / 4): u64;
	let src = 0z;
	for (p < (fbw * fbh): u64 && (src: u64) < n) {
		const y = p / (fbw: u64);
		const x = p % (fbw: u64);
		const dst = addr + (y * (pitch: u64) + x * 4): uintptr;
		// How many bytes of this row are left to write.
		let room = ((fbw: u64) - x) * 4;
		if (room > n - (src: u64)) {
			room = n - (src: u64);
		};
		// A whole run to the end of the row moves at once.
		architecture::memcpy(dst, (&data[src]: uintptr), room: size);
		src += room: size;
		p += room / 4;
	};
	// The rows the write covered, copied onto the card in one pass.
	const first = (off / 4) / (fbw: u64);
	const last = (p - 1) / (fbw: u64);
	present_rect(0, first: size, fbw, (last - first + 1): size);
	return n: size;
};

// Copies pixels off the screen into the caller's buffer, packed the same way.
export fn dev_read(buf: []u8, off: u64, n: size) size = {
	const total = dev_size();
	if (total == 0 || off >= total || n == 0) {
		return 0;
	};
	let got = (n: u64);
	if (off + got > total) {
		got = total - off;
	};
	let p = (off / 4): u64;
	let dst = 0z;
	for (p < (fbw * fbh): u64 && (dst: u64) < got) {
		const y = p / (fbw: u64);
		const x = p % (fbw: u64);
		const src = addr + (y * (pitch: u64) + x * 4): uintptr;
		let room = ((fbw: u64) - x) * 4;
		if (room > got - (dst: u64)) {
			room = got - (dst: u64);
		};
		architecture::memcpy((&buf[dst]: uintptr), src, room: size);
		dst += room: size;
		p += room / 4;
	};
	return dst;
};

fn addr_of(x: int, y: int) uintptr = {
	return addr + ((((y: size) * pitch) + ((x: size) * 4)): uintptr);
};

// Copies one row of a rectangle in 8-byte units. The direction depends on where
// the destination sits so an overlap does not clobber pixels still to be read.
fn copy_row(sx: int, sy: int, w: int, dx: int, dy: int) void = {
	const sb = addr_of(sx, sy);
	const db = addr_of(sx + dx, sy + dy);
	const n = (w: size) / 2z;
	const rem = (w: size) % 2z;
	if (db >= sb) {
		let i = n;
		for (i > 0) {
			i -= 1;
			*((db + (i * 8)): *u64) = *((sb + (i * 8)): *const u64);
		};
	} else {
		for (let i = 0z; i < n; i += 1) {
			*((db + (i * 8)): *u64) = *((sb + (i * 8)): *const u64);
		};
	};
	if (rem == 1) {
		const p = ((w: size) - 1) * 4;
		*((db + p): *u32) = *((sb + p): *const u32);
	};
};

// Slides a rectangle by (dx, dy) in place; the copy order keeps it correct when
// the source and destination overlap.
export fn move_rect(x: size, y: size, w: size, h: size, dx: int, dy: int) void = {
	if (!active() || (dx == 0 && dy == 0)) {
		return;
	};
	const sx = x: int;
	const sy = y: int;
	const iw = w: int;
	const ih = h: int;
	if (dy >= 0) {
		let j = ih - 1;
		for (j >= 0) {
			copy_row(sx, sy + j, iw, dx, dy);
			j -= 1;
		};
	} else {
		let j = 0;
		for (j < ih) {
			copy_row(sx, sy + j, iw, dx, dy);
			j += 1;
		};
	};
};