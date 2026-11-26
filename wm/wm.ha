use architecture;

@symbol("sched.bind_shell") fn sched_bind(id: size, wi: size) void;

// The small kernel half of the window system.
//
// The window manager itself is a user program now. This module holds only
// what the kernel must still know: which window has the focus, where the
// next byte of terminal output belongs, and the last frame a drawing program
// handed to /dev/fb. Those go out through files the manager reads, so there
// is no drawing code and no desktop policy left in the kernel.

def MAXOUT: size = 8192;
def FRAME: size = 640 * 400 * 4;

let out: [MAXOUT]u8 = [0...];
let outhead: size = 0;
let outtail: size = 0;
let outcount: size = 0;

let frame: [FRAME]u8 = [0...];
let framed: size = 0;
let framewin: size = 0;
let frameoff: u64 = 0;

let focus: size = 0;
let outwin: size = ~0z;

export fn focus_win() size = return focus;
export fn set_focus(wi: size) void = focus = wi;
export fn set_out(wi: size) void = outwin = wi;

// Where a byte written now belongs. The scheduler sets this on every thread
// switch; before it has, output goes to the focused window.
export fn out_target() size = {
	if (outwin != ~0z) {
		return outwin;
	};
	return focus;
};

// A byte of terminal output, with the window it was written to. Two bytes
// per character: the window number, then the byte.
export fn putc(ch: u8, wi: size) void = {
	if (outcount + 2 > len(out)) {
		return;
	};
	out[outtail] = wi: u8;
	outtail = (outtail + 1) % MAXOUT;
	out[outtail] = ch;
	outtail = (outtail + 1) % MAXOUT;
	outcount += 2;
};

// /dev/wmout: the stream of tagged bytes.
export fn out_read(buf: []u8, off: u64, n: size) size = {
	_ = off;
	let k = 0z;
	for (k < n && k < len(buf) && outcount > 0) {
		buf[k] = out[outhead];
		outhead = (outhead + 1) % MAXOUT;
		outcount -= 1;
		k += 1;
	};
	return k;
};

// /dev/fb from a drawing program lands in the frame holding area, tagged
// with the window it belongs to. The manager copies it into that window.
export fn frame_write(wi: size, off: u64, data: []u8) size = {
	if (off >= (FRAME: u64) || len(data) == 0) {
		return 0;
	};
	let n = len(data);
	if (off + (n: u64) > (FRAME: u64)) {
		n = ((FRAME: u64) - off): size;
	};
	architecture::memcpy((&frame[off: size]: uintptr),
			(&data[0]: uintptr), n);
	framewin = wi;
	frameoff = off;
	framed = n;
	return n;
};

fn put64(buf: []u8, at: size, v: u64) void = {
	for (let i = 0z; i < 8; i += 1) {
		buf[at + i] = (v >> ((i * 8): u64)): u8;
	};
};

fn get64(buf: []u8, at: size) u64 = {
	let v = 0u64;
	for (let i = 0z; i < 8; i += 1) {
		v |= (buf[at + i]: u64) << ((i * 8): u64);
	};
	return v;
};

// /dev/wmframe: the first 24 bytes say which window, at what offset, and
// how many bytes; the rest is the frame itself.
export fn frame_read(buf: []u8, off: u64, n: size) size = {
	if (n == 0 || len(buf) == 0) {
		return 0;
	};
	if (off < 24) {
		let hdr: [24]u8 = [0...];
		put64(hdr[..], 0, framewin: u64);
		put64(hdr[..], 8, frameoff);
		put64(hdr[..], 16, framed: u64);
		let k = 0z;
		for (k < n && (k: u64) < (24: u64) - off && k < len(buf)) {
			buf[k] = hdr[(off + (k: u64)): size];
			k += 1;
		};
		return k;
	};
	const at = off - 24;
	if (at >= (FRAME: u64) || framed == 0) {
		return 0;
	};
	let k = 0z;
	for (k < n && k < len(buf) && at + (k: u64) < framed: u64) {
		buf[k] = frame[(at + (k: u64)): size];
		k += 1;
	};
	return k;
};

// Window requests travel the other way. A program writes its name to
// /dev/win; the kernel leaves the request here and waits for the manager to
// answer with the window number and the size of its picture.
let req: [512]u8 = [0...];
let reqcount: size = 0;

export fn req_write(data: []u8, off: u64) size = {
	_ = off;
	if (reqcount + len(data) > len(req)) {
		return 0;
	};
	for (let i = 0z; i < len(data); i += 1) {
		req[reqcount] = data[i];
		reqcount += 1;
	};
	return len(data);
};

export fn req_read(buf: []u8, off: u64, n: size) size = {
	_ = off;
	let k = 0z;
	for (k < n && k < len(buf) && reqcount > 0) {
		buf[k] = req[0];
		for (let i = 1z; i < reqcount; i += 1) {
			req[i - 1] = req[i];
		};
		reqcount -= 1;
		k += 1;
	};
	return k;
};

let reply: [24]u8 = [0...];
let has_answer = false;

// /dev/wmreply: the manager's answer, three words - window, width, height.
export fn reply_write(data: []u8, off: u64) size = {
	_ = off;
	if (len(data) < 24) {
		return 0;
	};
	for (let i = 0z; i < 24; i += 1) {
		reply[i] = data[i];
	};
	has_answer = true;
	return len(data);
};

export fn answered() bool = has_answer;

export fn reply_window() size = get64(reply[..], 0): size;

export fn reply_dims(w: *size, h: *size) void = {
	*w = get64(reply[..], 8): size;
	*h = get64(reply[..], 16): size;
};

// The picture size can change when the player drags the window.
let dimw: size = 0;
let dimh: size = 0;

export fn set_dims(w: size, h: size) void = {
	dimw = w;
	dimh = h;
};

export fn dims(w: *size, h: *size) void = {
	*w = dimw;
	*h = dimh;
};

// A freshly opened terminal window asks its shell to print a prompt.
let fresh = false;

export fn set_fresh() void = fresh = true;

export fn take_fresh() bool = {
	const was = fresh;
	fresh = false;
	return was;
};

// The manager spawns a shell for a new window and tells the kernel which
// window it belongs to, so keystrokes reach the right one.
export fn bind_shell(data: []u8, off: u64) size = {
	_ = off;
	if (len(data) < 2) {
		return 0;
	};
	sched_bind(data[0]: size, data[1]: size);
	return len(data);
};
