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

fn terminal() bool = {
	let did = false;
	for (let pass = 0z; pass < 16; pass += 1) {
		let b: [512]u8 = [0...];
		const n = rt::readfile("/dev/sessionout", b[..]);
		if (n == 0) {
			break;
		};
		did = true;
		let i = 0z;
		for (i + 1 < n) {
			feed(b[i]: size, b[i + 1]);
			i += 2;
		};
	};
	return did;
};

fn requests() bool = {
	let b: [64]u8 = [0...];
	const n = rt::readfile("/dev/gfxreq", b[..]);
	if (n < 3) {
		return false;
	};
	const name = b[1..1 + (b[0]: size)];
	const id = b[1 + (b[0]: size)]: size;
	const from = b[2 + (b[0]: size)]: size;
	const wi = claim_gfx(name, id, from);
	set_out_win(wi);
	let w = 0z;
	let h = 0z;
	gfx_dims(&w, &h);
	// The kernel's no-session value is all ones. Kit's NONE is only a small
	// marker for an unused slot, so it has to be translated here or a failed
	// request binds a program to a session that does not exist.
	const answer = if (wi == NONE) ~0z else wi;
	let reply: [32]u8 = [0...];
	put64(reply[..], 0, answer: u64);
	put64(reply[..], 8, w: u64);
	put64(reply[..], 16, h: u64);
	put64(reply[..], 24, gfx_surface(): u64);
	_ = rt::writefile("/dev/gfxreply", reply[..]);
	return true;
};

let lastframe = 0u64;
let lastflip = 0u64;

def MAXFRAME: size = 1280 * 1024 * 4;

fn frames(scratch: uintptr) bool = {
	let hdr: [32]u8 = [0...];
	const n = rt::readat("/dev/gfxframe", 0, hdr[..]);
	if (n < 32) {
		return false;
	};
	const seq = get64(hdr[..], 24);
	if (seq == lastframe) {
		return false;
	};
	lastframe = seq;
	const wi = get64(hdr[..], 0): size;
	const off = get64(hdr[..], 8);
	const count = get64(hdr[..], 16): size;
	if (wi == NONE || count == 0 || count > MAXFRAME) {
		return false;
	};
	const got = rt::readat("/dev/gfxframe", 32, bytes(scratch, count));
	if (got > 0) {
		draw_frame(wi, bytes(scratch, got), off);
	};
	return true;
};

// Programs that map a shared surface ring /dev/flip when a frame is ready.
// The pixels are already in the window's buffer, so this is only a doorbell.
fn flips() bool = {
	let hdr: [16]u8 = [0...];
	const n = rt::readfile("/dev/flip", hdr[..]);
	if (n < 16) {
		return false;
	};
	const seq = get64(hdr[..], 8);
	if (seq == lastflip) {
		return false;
	};
	lastflip = seq;
	return surface_show(get64(hdr[..], 0): size);
};

// A drawing program has ended. The kernel only tells us the two numbers it
// knows; kit decides whether they named one of its windows and clears it.
fn exits() bool = {
	let b: [32]u8 = [0...];
	const n = rt::readfile("/dev/sessionexit", b[..]);
	let i = 0z;
	for (i + 1 < n) {
		release_owner(b[i]: size);
		i += 2;
	};
	return i > 0;
};

// A new terminal window needs a shell of its own. It has to start in that
// session before it says anything, or its banner and prompt land in the
// terminal the window was opened from. The kernel binds the shell to the
// window afterwards so its keystrokes go to the right place as well.
fn on_new_window(wi: size) void = {
	const s: [1]u8 = [wi: u8];
	_ = rt::writefile("/dev/sessionspawn", s[..]);
	const id = rt::spawn_shared("/sh");
	if (id == ~0u64) {
		return;
	};
	const b: [2]u8 = [id: u8, wi: u8];
	_ = rt::writefile("/dev/sessionbind", b[..]);
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
		_ = rt::writefile("/dev/sessionfresh", one[..]);
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
		_ = rt::writefile("/dev/gfxdims", d[..]);
	};
	const wi = focus_win();
	if (wi != lastfocus) {
		lastfocus = wi;
		const one: [1]u8 = [wi: u8];
		_ = rt::writefile("/dev/sessionfocus", one[..]);
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
	// Room for the largest frame a drawing window can hand over.
	const scratch = rt::page_alloc(1282);
	if (scratch == 0) {
		return;
	};
	let ev: [8]u8 = [0...];
	for (true) {
		let work = terminal();
		if (requests()) {
			work = true;
		};
		if (frames(scratch)) {
			work = true;
		};
		if (flips()) {
			work = true;
		};
		if (exits()) {
			work = true;
		};
		// Poll for a few pointer edges, not thirty-two. Each try pokes the
		// PS/2 controller with interrupts off, so a long empty poll made the
		// whole desktop stutter while the pointer was sitting still.
		for (let pass = 0z; pass < 4; pass += 1) {
			const n = rt::readfile("/dev/mouse", ev[..]);
			if (n != 8) {
				break;
			};
			const e = *(&ev: *mouseev);
			_ = mouse(e.dx: int, e.dy: int, e.btn);
			work = true;
		};
		report_state();
		flush();
		sync();
		// Frames arrive faster than this loop can drain them, so give the
		// game and the shell a turn every time rather than after eight
		// expensive repaints.
		rt::cop();
	};
};
