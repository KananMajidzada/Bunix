use lib;
use rt;

// base64 [-d] [file]
//
// Base64, as it appears in an attachment line or a PEM header. Encoding is
// three bytes in to four characters out; decoding is the other way round. The
// alphabet here is the usual one, with the trailing pad, and a line break every
// 76 characters because that is what the text it came from expects.

const ALPHA: str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const LINE: size = 76;

fn alphabet() []u8 = {
	return *(&ALPHA: *[]u8);
};

fn value(c: u8) int = {
	const a = alphabet();
	let v: int = -1;
	for (let i = 0z; i < len(a); i += 1) {
		if (a[i] == c) {
			v = i: int;
			break;
		};
	};
	if (v >= 0) {
		return v;
	};
	// The two characters that are not in the alphabet but mean something.
	if (c == ('=': u8)) {
		return -2;
	};
	return -1;
};

fn encode(text: []u8) void = {
	const a = alphabet();
	let col = 0z;
	for (let i = 0z; i < len(text); i += 3) {
		// Held as u32 so the shifts below stay in one type: a shift of a u8
		// widens, and an index has to be a size again to be worth anything.
		const b0 = text[i]: u32;
		const have1 = i + 1 < len(text);
		const have2 = i + 2 < len(text);
		const b1 = if (have1) text[i + 1]: u32 else (0: u32);
		const b2 = if (have2) text[i + 2]: u32 else (0: u32);

		rt::putc(a[((b0 >> 2) & 0x3f): size]);
		rt::putc(a[(((b0 & 0x03) << 4) | (b1 >> 4)): size]);
		// The last group is short, and what is missing becomes padding rather
		// than whatever happened to be left in the register.
		if (have1) {
			rt::putc(a[(((b1 & 0x0f) << 2) | (b2 >> 6)): size]);
		} else {
			rt::putc('=': u8);
		};
		if (have2) {
			rt::putc(a[(b2 & 0x3f): size]);
		} else {
			rt::putc('=': u8);
		};

		col += 4;
		if (col >= LINE) {
			rt::println("");
			col = 0;
		};
	};
	if (col > 0) {
		rt::println("");
	};
};

fn decode(text: []u8) void = {
	let acc: u32 = 0;
	let bits: u32 = 0;
	for (let i = 0z; i < len(text); i += 1) {
		const c = text[i];
		// Line breaks and padding are not part of the data.
		if (c == ('\n': u8) || c == ('\r': u8) || c == (' ': u8) || c == ('=': u8)) {
			continue;
		};
		const v = value(c);
		if (v < 0) {
			rt::println("base64: a character that is not in the alphabet");
			return;
		};
		acc = (acc << 6) | (v: u32);
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			rt::putc((acc >> bits): u8);
		};
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let decoding = false;
	for (let k = 0z; pos < len(args); k += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('d': u8)) {
			decoding = true;
			pos = lib::skip_space(args, pos + len(tok));
			continue;
		};
		if (tok[0] == ('-': u8)) {
			rt::print("base64: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		break;
	};

	const path = lib::arg_n(args, if (decoding) 1 else 0);
	if (len(path) == 0) {
		// No file named, so the keyboard is the input, closed with Ctrl-D.
		let buf: [1024]u8 = [0...];
		let n = 0z;
		for (true) {
			const c = rt::getchar();
			if (c == 4) {
				break;
			};
			if (n < len(buf)) {
				buf[n] = c;
				n += 1;
			};
		};
		if (decoding) {
			decode(buf[..n]);
		} else {
			encode(buf[..n]);
		};
		return;
	};

	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("base64: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	if (decoding) {
		decode(text);
	} else {
		encode(text);
	};
	lib::release(text);
};