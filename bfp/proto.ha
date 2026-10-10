// Wire: size[4] type[1] tag[2] then a body; a reply is the request type + 1.

export def TPROTO: u8 = 1;
export def RPROTO: u8 = 2;
export def TATTACH: u8 = 3;
export def RATTACH: u8 = 4;
export def RERROR: u8 = 5;
export def TWALK: u8 = 6;
export def RWALK: u8 = 7;
export def TOPEN: u8 = 8;
export def ROPEN: u8 = 9;
export def TREAD: u8 = 10;
export def RREAD: u8 = 11;
export def TCLUNK: u8 = 12;
export def RCLUNK: u8 = 13;

export def NOTAG: u16 = 0xFFFF;
export def NOHANDLE: u32 = 0xFFFFFFFF;

// ident type bits.
export def IDDIR: u8 = 0x80;

// The protocol name and revision exchanged by TPROTO.
export def REVISION: str = "bfp1";

// Header size: size[4] type[1] tag[2].
def HDR: size = 7;

export type header = struct {
	sz: u32,
	typ: u8,
	tag: u16,
};

export fn begin(w: *writer, typ: u8, tag: u16) void = {
	w_u32(w, 0);
	w_u8(w, typ);
	w_u16(w, tag);
};

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

fn write_ident(w: *writer, path: u64, typ: u8) void = {
	w_u8(w, typ);
	w_u32(w, 0);
	w_u64(w, path);
};

export type slot = struct {
	inuse: bool,
	path: u64,
	typ: u8,
};

export type server = struct {
	content: str,
	handles: [16]slot,
};

export fn new(content: str) server = {
	return server {
		content = content,
		handles = [slot { inuse = false, path = 0, typ = 0 }...],
	};
};

export fn handle(s: *server, in: []u8, out: []u8) size = {
	const h = parse_header(in);
	let r = reader { buf = in, off = HDR };
	let w = writer { buf = out, off = 0 };
	begin(&w, h.typ + 1, h.tag);

	switch (h.typ) {
	case TPROTO =>
		do_proto(&w, &r);
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

fn do_proto(w: *writer, r: *reader) void = {
	const msize = r_u32(r);
	_ = r_bytes(r);
	w_u32(w, msize);
	w_str(w, REVISION);
};

fn do_attach(s: *server, w: *writer, r: *reader) void = {
	const h = r_u32(r);
	_ = r_u32(r);
	_ = r_bytes(r);
	_ = r_bytes(r);
	s.handles[h: size] = slot { inuse = true, path = 0, typ = IDDIR };
	write_ident(w, 0, IDDIR);
};

fn do_walk(s: *server, w: *writer, r: *reader) void = {
	_ = r_u32(r);
	const nh = r_u32(r);
	const n = r_u16(r);
	if (n == 1 && asstr(r_bytes(r)) == "hello") {
		s.handles[nh: size] = slot { inuse = true, path = 1, typ = 0 };
		w_u16(w, 1);
		write_ident(w, 1, 0);
	} else {
		w_u16(w, 0);
	};
};

fn do_open(s: *server, w: *writer, r: *reader) void = {
	const h = r_u32(r);
	_ = r_u8(r);
	const f = s.handles[h: size];
	write_ident(w, f.path, f.typ);
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
	const h = r_u32(r);
	s.handles[h: size].inuse = false;
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

export fn slurp(s: *server, name: str) []u8 = {
	let w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TPROTO, NOTAG);
	w_u32(&w, 8192);
	w_str(&w, REVISION);
	_ = call(s, &w);

	w = writer { buf = reqbuf[..], off = 0 };
	begin(&w, TATTACH, 0);
	w_u32(&w, 0);
	w_u32(&w, NOHANDLE);
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
