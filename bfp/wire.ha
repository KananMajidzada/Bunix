export type ident = struct {
	typ: u8,
	vers: u32,
	path: u64,
};

export type writer = struct {
	buf: []u8,
	off: size,
};

export type reader = struct {
	buf: []u8,
	off: size,
};

export fn w_u8(w: *writer, v: u8) void = {
	w.buf[w.off] = v;
	w.off += 1;
};

export fn w_u16(w: *writer, v: u16) void = {
	w_u8(w, (v & 0xFF): u8);
	w_u8(w, ((v >> 8) & 0xFF): u8);
};

export fn w_u32(w: *writer, v: u32) void = {
	w_u16(w, (v & 0xFFFF): u16);
	w_u16(w, ((v >> 16) & 0xFFFF): u16);
};

export fn w_u64(w: *writer, v: u64) void = {
	w_u32(w, (v & 0xFFFFFFFF): u32);
	w_u32(w, ((v >> 32) & 0xFFFFFFFF): u32);
};

export fn w_bytes(w: *writer, b: []u8) void = {
	for (let i = 0z; i < len(b); i += 1) {
		w_u8(w, b[i]);
	};
};

export fn w_str(w: *writer, s: str) void = {
	const b = *(&s: *[]u8);
	w_u16(w, len(b): u16);
	w_bytes(w, b);
};

export fn r_u8(r: *reader) u8 = {
	const v = r.buf[r.off];
	r.off += 1;
	return v;
};

export fn r_u16(r: *reader) u16 = {
	const lo = r_u8(r): u16;
	const hi = r_u8(r): u16;
	return lo | (hi << 8);
};

export fn r_u32(r: *reader) u32 = {
	const lo = r_u16(r): u32;
	const hi = r_u16(r): u32;
	return lo | (hi << 16);
};

export fn r_u64(r: *reader) u64 = {
	const lo = r_u32(r): u64;
	const hi = r_u32(r): u64;
	return lo | (hi << 32);
};

// Returns a view of the next length-prefixed byte string in the message.
export fn r_bytes(r: *reader) []u8 = {
	const n = r_u16(r): size;
	const s = r.buf[r.off..r.off + n];
	r.off += n;
	return s;
};

export fn asstr(b: []u8) str = {
	return *(&b: *str);
};
