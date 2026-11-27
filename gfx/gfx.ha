use architecture;

// The drawing channel between programs and a compositor.
//
// Nothing here lays out a desktop or decides where a picture goes. A program
// that draws sends its pixels to /dev/fb; the kernel keeps the newest frame in
// one holding area and a compositor reads it through /dev/gfxframe. Requests
// for a drawing surface and their answers travel through /dev/gfxreq and
// /dev/gfxreply. The surface size published by the compositor is what a
// drawing program reads back from /proc/fb and /dev/win.

// The holding area covers every framebuffer size the machine offers. A small
// one used to clip a picture after the player enlarged its window.
def FRAME: size = 1280 * 1024 * 4;

let frame: [FRAME]u8 = [0...];
let framed: size = 0;
let frameseq: u64 = 0;
let frameses: size = 0;
let frameoff: u64 = 0;

// /dev/fb from a drawing program lands in the holding area, tagged with the
// session it belongs to. The compositor copies it into that session's surface.
export fn frame_write(ses: size, off: u64, data: []u8) size = {
	if (off >= (FRAME: u64) || len(data) == 0) {
		return 0;
	};
	let n = len(data);
	if (off + (n: u64) > (FRAME: u64)) {
		n = ((FRAME: u64) - off): size;
	};
	architecture::memcpy((&frame[off: size]: uintptr),
			(&data[0]: uintptr), n);
	frameses = ses;
	frameoff = off;
	framed = n;
	frameseq += 1;
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

// /dev/gfxframe: the first 32 bytes say which session, at what offset, how
// many bytes, and a sequence number; the rest is the frame itself.
export fn frame_read(buf: []u8, off: u64, n: size) size = {
	if (n == 0 || len(buf) == 0) {
		return 0;
	};
	if (off < 32) {
		let hdr: [32]u8 = [0...];
		put64(hdr[..], 0, frameses: u64);
		put64(hdr[..], 8, frameoff);
		put64(hdr[..], 16, framed: u64);
		put64(hdr[..], 24, frameseq);
		let k = 0z;
		for (k < n && (k: u64) < (32: u64) - off && k < len(buf)) {
			buf[k] = hdr[(off + (k: u64)): size];
			k += 1;
		};
		return k;
	};
	const at = off - 32;
	if (at >= (FRAME: u64) || framed == 0) {
		return 0;
	};
	let k = n;
	if (k > len(buf)) {
		k = len(buf);
	};
	if (at + (k: u64) > (framed: u64)) {
		k = (framed: u64 - at): size;
	};
	if (k > 0) {
		architecture::memcpy((&buf[0]: uintptr),
				(&frame[at: size]: uintptr), k);
	};
	return k;
};

// A program writes its name to /dev/win to ask for a drawing surface. The
// kernel leaves the request here for a compositor to answer with a session
// number and the size of the picture.
let req: [512]u8 = [0...];
let reqcount: size = 0;

export fn req_write(data: []u8, off: u64) size = {
	_ = off;
	if (reqcount + len(data) > len(req)) {
		return 0;
	};
	// A new request invalidates the last answer. Without this a program
	// opening its second window sails past the wait in /dev/win using the
	// previous session number, before the compositor has made the new
	// surface, and its first frames go to the wrong picture.
	has_answer = false;
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

// /dev/gfxreply: the compositor's answer, three words - session, width, height.
export fn reply_write(data: []u8, off: u64) size = {
	_ = off;
	if (len(data) < 24) {
		return 0;
	};
	for (let i = 0z; i < 24; i += 1) {
		reply[i] = data[i];
	};
	// The answer carries the picture's size as well as its session. Publish
	// the size here, so a program reading /dev/win straight after asking for
	// a window sees it at once instead of racing the compositor's next loop.
	set_dims(get64(reply[..], 8): size, get64(reply[..], 16): size);
	has_answer = true;
	return len(data);
};

export fn answered() bool = has_answer;

export fn reply_session() size = get64(reply[..], 0): size;

// The surface size changes when the player drags a window. The compositor
// publishes it here so programs can read their own picture's size again.
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
