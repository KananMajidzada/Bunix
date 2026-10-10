// A first cut at 9P2000: message framing, a tiny in-memory file server, and a
// client that reads a file through it. Everything here is plain data, so the
// same code will serve real channels once there are processes and file
// descriptors to carry them.

export def TVERSION: u8 = 100;
export def RVERSION: u8 = 101;
export def TATTACH: u8 = 104;
export def RATTACH: u8 = 105;
export def RERROR: u8 = 107;
export def TWALK: u8 = 110;
export def RWALK: u8 = 111;
export def TOPEN: u8 = 112;
export def ROPEN: u8 = 113;
export def TREAD: u8 = 116;
export def RREAD: u8 = 117;
export def TCLUNK: u8 = 120;
export def RCLUNK: u8 = 121;

export def NOTAG: u16 = 0xFFFF;
export def NOFID: u32 = 0xFFFFFFFF;

export def QTDIR: u8 = 0x80;

// Header size: size[4] type[1] tag[2].
def HDR: size = 7;

export type header = struct {
	sz: u32,
	typ: u8,
	tag: u16,
};

// Writes the message header with a placeholder size.
export fn begin(w: *writer, typ: u8, tag: u16) void = {
	w_u32(w, 0);
	w_u8(w, typ);
	w_u16(w, tag);
};

// Patches the size field and returns the length of the finished message.
export fn finish(w: *writer) size = {
	const n = w.off: u32;
	w.buf[0] = (n & 0xFF): u8;
	w.buf[1] = ((n >> 8) & 0xFF): u8;
	w.buf[2] = ((n >> 16) & 0xFF): u8;
	w.buf[3] = ((n >> 24) & 0xFF): u8;
	return w.off;
};

export fn parse_header(buf: []u8) header = {
	let r = reader { buf = buf, off = 0 };
	return header {
		sz = r_u32(&r),
		typ = r_u8(&r),
		tag = r_u16(&r),
	};
};

fn write_qid(w: *writer, path: u64, typ: u8) void = {
	w_u8(w, typ);
	w_u32(w, 0);
	w_u64(w, path);
};

// A fid names an open file on the server side.
export type slot = struct {
	inuse: bool,
	path: u64,
	typ: u8,
};

export type server = struct {
	content: str,
	fids: [16]slot,
};

export fn new(content: str) server = {
	return server {
		content = content,
		fids = [slot { inuse = false, path = 0, typ = 0 }...],
	};
};

// Handles one request and writes one response. The root is a directory at path
// zero; the single file "hello" is at path one.
export fn handle(s: *server, in: []u8, out: []u8) size = {
	const h = parse_header(in);
	let r = reader { buf = in, off = HDR };
	let w = writer { buf = out, off = 0 };
	begin(&w, h.typ + 1, h.tag);

	switch (h.typ) {
	case TVERSION =>
		do_version(&w, &r);
	case TATTACH =>
		do_attach(s, &w, &r);
	case TWALK =>
		do_walk(s, &w, &r);
	case TOPEN =>
		do_open(s, &w, &r);
	case TREAD =>
		do_read(s, &w, &r);
	case TCLUNK =>
		do_clunk(s, &w, &r);
	case =>
		do_error(&w, h.tag);
	};

	return finish(&w);
};

fn do_version(w: *writer, r: *reader) void = {
	const msize = r_u32(r);
	_ = r_bytes(r);
	w_u32(w, msize);
	w_str(w, "9P2000");
};

fn do_attach(s: *server, w: *writer, r: *reader) void = {
	const fid = r_u32(r);
	_ = r_u32(r);
	_ = r_bytes(r);
	_ = r_bytes(r);
	s.fids[fid: size] = slot { inuse = true, path = 0, typ = QTDIR };
	write_qid(w, 0, QTDIR);
};

fn do_walk(s: *server, w: *writer, r: *reader) void = {
	_ = r_u32(r);
	const nfid = r_u32(r);
	const n = r_u16(r);
	if (n == 1 && asstr(r_bytes(r)) == "hello") {
		s.fids[nfid: size] = slot { inuse = true, path = 1, typ = 0 };
		w_u16(w, 1);
		write_qid(w, 1, 0);
	} else {
		w_u16(w, 0);
	};
};

fn do_open(s: *server, w: *writer, r: *reader) void = {
	const fid = r_u32(r);
	_ = r_u8(r);
	const f = s.fids[fid: size];
	write_qid(w, f.path, f.typ);
	w_u32(w, 0);
};

fn do_read(s: *server, w: *writer, r: *reader) void = {
	_ = r_u32(r);
	_ = r_u64(r);
	const count = r_u32(r): size;
	const body = *(&s.content: *[]u8);
	let n = len(body);
	if (n > count) {
		n = count;
	};
	w_u32(w, n: u32);
	w_bytes(w, body[..n]);
};

fn do_clunk(s: *server, w: *writer, r: *reader) void = {
	const fid = r_u32(r);
	s.fids[fid: size].inuse = false;
};

fn do_error(w: *writer, tag: u16) void = {
	w.off = 0;
	begin(w, RERROR, tag);
	w_str(w, "unsupported");
};

// Scratch buffers for the loopback client.
let reqbuf: [1024]u8 = [0...];
let resbuf: [2048]u8 = [0...];
let filebuf: [512]u8 = [0...];

fn call(s: *server, w: *writer) []u8 = {
	const n = finish(w);
	const rn = handle(s, w.buf[..n], resbuf[..]);
	return resbuf[..rn];
};

// Performs version, attach, walk, open, read and clunk over the loopback and
// returns the file contents.
export fn slurp(s: *server, name: str) []u8 = {
	let w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TVERSION, NOTAG);
	w_u32(&w, 8192);
	w_str(&w, "9P2000");
	_ = call(s, &w);

	w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TATTACH, 0);
	w_u32(&w, 0);
	w_u32(&w, NOFID);
	w_str(&w, "bunix");
	w_str(&w, "");
	_ = call(s, &w);

	w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TWALK, 1);
	w_u32(&w, 0);
	w_u32(&w, 1);
	w_u16(&w, 1);
	w_str(&w, name);
	_ = call(s, &w);

	w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TOPEN, 2);
	w_u32(&w, 1);
	w_u8(&w, 0);
	_ = call(s, &w);

	w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TREAD, 3);
	w_u32(&w, 1);
	w_u64(&w, 0);
	w_u32(&w, 512);
	const resp = call(s, &w);
	let r = reader { buf = resp, off = HDR };
	const cnt = r_u32(&r): size;
	for (let i = 0z; i < cnt; i += 1) {
		filebuf[i] = r_u8(&r);
	};

	w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TCLUNK, 4);
	w_u32(&w, 1);
	_ = call(s, &w);

	return filebuf[..cnt];
};

// The version string negotiated by the last slurp, for callers that want to
// show it.
export fn negotiated_msize(s: *server, msize: u32) void = {
	let w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TVERSION, NOTAG);
	w_u32(&w, msize);
	w_str(&w, "9P2000");
	_ = call(s, &w);
};
