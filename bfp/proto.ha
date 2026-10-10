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
export def TWRITE: u8 = 14;
export def RWRITE: u8 = 15;

export def NOTAG: u16 = 0xFFFF;
export def NOHANDLE: u32 = 0xFFFFFFFF;

// ident type bits.
export def IDDIR: u8 = 0x80;

// The protocol name and revision exchanged by TPROTO.
export def REVISION: str = "bfp1";

export def HDR: size = 7;

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

export fn write_ident(w: *writer, path: u64, typ: u8) void = {
	w_u8(w, typ);
	w_u32(w, 0);
	w_u64(w, path);
};
