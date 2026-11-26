use fb;
use rt;

// The window manager as a user program.
//
// It owns the picture on the screen and the desktop's behaviour; the kernel
// only passes it bytes and frames through files. That is the same deal every
// other program gets: this one happens to draw the desktop.

type mouseev = struct @packed {
	dx: i16,
	dy: i16,
	btn: u8,
	pad: [5]u8,
};

type raw = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

let rawbuf = raw { data = 0, length = 0, capacity = 0 };
fn bytes(p: uintptr, n: size) []u8 = {
	rawbuf.data = p;
	rawbuf.length = n;
	rawbuf.capacity = n;
	return *(&rawbuf: *[]u8);
};

fn put64(b: []u8, at: size, v: u64) void = {
	for (let i = 0z; i < 8; i += 1) {
		b[at + i] = (v >> ((i * 8): u64)): u8;
	};
};

fn get64(b: []u8, at: size) u64 = {
	let v = 0u64;
	for (let i = 0z; i < 8; i += 1) {
		v |= (b[at + i]: u64) << ((i * 8): u64);
	};
	return v;
};

fn terminal() void = {
	let b: [512]u8 = [0...];
	const n = rt::readfile("/dev/wmout", b[..]);
	let i = 0z;
	for (i + 1 < n) {
		feed(b[i]: size, b[i + 1]);
		i += 2;
	};
};

fn requests() void = {
	let b: [64]u8 = [0...];
	const n = rt::readfile("/dev/wmreq", b[..]);
	if (n < 3) {
		return;
	};
	const name = b[1..1 + (b[0]: size)];
	const id = b[1 + (b[0]: size)]: size;
	const from = b[2 + (b[0]: size)]: size;
	const wi = claim_gfx(name, id, from);
	set_out_win(wi);
	let w = 0z;
	let h = 0z;
	gfx_dims(&w, &h);
	let reply: [24]u8 = [0...];
	put64(reply[..], 0, wi: u64);
	put64(reply[..], 8, w: u64);
	put64(reply[..], 16, h: u64);
	_ = rt::writefile("/dev/wmreply", reply[..]);
};

let lastframe = 0u64;

fn frames(scratch: uintptr) void = {
	let hdr: [32]u8 = [0...];
	const n = rt::readat("/dev/wmframe", 0, hdr[..]);
	if (n < 32) {
		return;
	};
	const seq = get64(hdr[..], 24);
	if (seq == lastframe) {
		return;
	};
	lastframe = seq;
	const wi = get64(hdr[..], 0): size;
	const off = get64(hdr[..], 8);
	const count = get64(hdr[..], 16): size;
	if (wi == NONE || count == 0 || count > 640 * 400 * 4) {
		return;
	};
	const got = rt::readat("/dev/wmframe", 32, bytes(scratch, count));
	if (got > 0) {
		draw_frame(wi, bytes(scratch, got), off);
	};
};

// A new terminal window needs a shell of its own. The kernel binds it to
// the window so its keystrokes go to the right place.
fn on_new_window(wi: size) void = {
	const id = rt::spawn_shared("/sh");
	if (id == ~0u64) {
		return;
	};
	const b: [2]u8 = [id: u8, wi: u8];
	_ = rt::writefile("/dev/wmbind", b[..]);
};

// Deleting a drawing window ends the program that owned it.
fn on_close_window(id: size) void = {
	_ = rt::kill(id);
};

let lastw: size = ~0z;
let lasth: size = ~0z;
let lastfocus: size = ~0z;

fn report_state() void = {
	if (take_fresh()) {
		const one: [1]u8 = [0];
		_ = rt::writefile("/dev/wmfresh", one[..]);
	};
	let w = 0z;
	let h = 0z;
	gfx_dims(&w, &h);
	if (w != lastw || h != lasth) {
		lastw = w;
		lasth = h;
		let d: [16]u8 = [0...];
		put64(d[..], 0, w: u64);
		put64(d[..], 8, h: u64);
		_ = rt::writefile("/dev/wmdims", d[..]);
	};
	const wi = focus_win();
	if (wi != lastfocus) {
		lastfocus = wi;
		const one: [1]u8 = [wi: u8];
		_ = rt::writefile("/dev/wmfocus", one[..]);
	};
};

export @symbol("main") fn main() void = {
	fb::init();
	if (!fb::active()) {
		rt::println("wm: no framebuffer");
		return;
	};
	new_win_hook = &on_new_window;
	close_hook = &on_close_window;
	begin();
	const scratch = rt::page_alloc(256);
	if (scratch == 0) {
		return;
	};
	let ev: [8]u8 = [0...];
	for (true) {
		terminal();
		requests();
		frames(scratch);
		const n = rt::readfile("/dev/mouse", ev[..]);
		if (n == 8) {
			const e = *(&ev: *mouseev);
			_ = mouse(e.dx: int, e.dy: int, e.btn);
		};
		report_state();
		sync();
		rt::cop();
	};
};
