use architecture;
use mem;

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

// Surfaces are frames a compositor maps into a program's address space. The
// program writes pixels straight into them and announces a flip; the kernel
// never copies the picture. The bit about "surface" is ours: the kernel only
// knows about frames, a size, and who has the mapping.
def MAXSURF: size = 8;
def SURFPAGES: size = 1280;	// 1280x1024x4, every mode the machine offers
let surf_used: [MAXSURF]bool = [false...];
let surf_count: [MAXSURF]size = [0...];
let surf_w: [MAXSURF]size = [0...];
let surf_h: [MAXSURF]size = [0...];
// The allocator gives a surface one contiguous run of frames, so only the
// first one needs keeping. A table of every frame would cost 80 KiB of kernel
// data for pictures that are rarely more than one surface at a time.
let surf_base: [MAXSURF]uintptr = [0...];

// Allocates a surface owned by nobody in particular. A compositor maps it into
// its own window and hands the id to the drawing program, which maps the same
// frames. The frames outlive both mappings until the surface is released.
export fn surface_new(w: size, h: size) size = {
	if (w == 0 || h == 0) {
		return 0;
	};
	const pages = ((w * h * 4 + 4095) / 4096);
	if (pages == 0 || pages > SURFPAGES) {
		return 0;
	};
	for (let i = 0z; i < MAXSURF; i += 1) {
		if (surf_used[i]) {
			continue;
		};
		const base = mem::frames_alloc(pages: u64);
		if (base == 0) {
			return 0;
		};
		for (let j = 0z; j < pages; j += 1) {
			architecture::store64(base + ((j * 4096): uintptr), 0, 512);
		};
		surf_base[i] = base;
		surf_used[i] = true;
		surf_count[i] = pages;
		surf_w[i] = w;
		surf_h[i] = h;
		return i + 1;
	};
	return 0;
};

export fn surface_release(id: size) bool = {
	if (id == 0 || id > MAXSURF || !surf_used[id - 1]) {
		return false;
	};
	const i = id - 1;
	for (let j = 0z; j < surf_count[i]; j += 1) {
		mem::release(surf_base[i] + ((j * 4096): uintptr));
	};
	surf_base[i] = 0;
	surf_used[i] = false;
	surf_count[i] = 0;
	surf_w[i] = 0;
	surf_h[i] = 0;
	return true;
};

export fn surface_count(id: size) size = {
	if (id == 0 || id > MAXSURF || !surf_used[id - 1]) {
		return 0;
	};
	return surf_count[id - 1];
};

export fn surface_frame(id: size, i: size) uintptr = {
	if (i >= surface_count(id)) {
		return 0;
	};
	return surf_base[id - 1] + ((i * 4096): uintptr);
};

export fn surface_dims(id: size, w: *size, h: *size) bool = {
	if (id == 0 || id > MAXSURF || !surf_used[id - 1]) {
		return false;
	};
	*w = surf_w[id - 1];
	*h = surf_h[id - 1];
	return true;
};

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

let reply: [32]u8 = [0...];
let has_answer = false;

// /dev/gfxreply: four words - session, width, height, surface. The surface is
// the shared picture the compositor made for this window; a program that can
// map it never needs to send frame bytes through the kernel at all.
export fn reply_write(data: []u8, off: u64) size = {
	_ = off;
	if (len(data) < 32) {
		return 0;
	};
	for (let i = 0z; i < 32; i += 1) {
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

export fn reply_surface() size = get64(reply[..], 24): size;

// /dev/flip: a drawing program writes the surface id after it has finished a
// frame. The compositor reads the id and a sequence number and shows that one
// surface. It is a doorbell, not a pixel channel.
let flipid: u64 = 0;
let flipseq: u64 = 0;

export fn flip_write(data: []u8, off: u64) size = {
	_ = off;
	if (len(data) < 8) {
		return 0;
	};
	flipid = get64(data[..], 0);
	flipseq += 1;
	return len(data);
};

export fn flip_read(buf: []u8, off: u64, n: size) size = {
	if (n == 0 || len(buf) == 0 || off >= 16) {
		return 0;
	};
	let hdr: [16]u8 = [0...];
	put64(hdr[..], 0, flipid);
	put64(hdr[..], 8, flipseq);
	let k = 0z;
	for (k < n && k < len(buf) && (k: u64) < 16 - off) {
		buf[k] = hdr[(off + (k: u64)): size];
		k += 1;
	};
	return k;
};

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
