use lib;
use rt;

// od [-c] [-o] [-x] [file [offset]]
//
// A dump of bytes. hd in the shell does the same job as a hex dump from an
// offset, which is what you want when a file will not load; od is the other
// half of the story, the one that also shows the bytes as characters and as
// octal, which is what makes a stray byte visible.
//
// With no file named it reads the keyboard, so it can be used on something
// that only ever exists as output.

let showchar: bool = false;
let showoct: bool = false;
let showhex: bool = true;

// Sixteen bytes to a line, which is what a terminal is wide enough for.
def WIDTH: size = 16;

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

// The byte as it is meant to be looked at rather than as it is stored.
fn character(c: u8) void = {
	if (c == ('\n': u8)) {
		rt::print("\\n");
		return;
	};
	if (c == ('\t': u8)) {
		rt::print("\\t");
		return;
	};
	if (c == ('\r': u8)) {
		rt::print("\\r");
		return;
	};
	if (c == 0) {
		rt::print("\\0");
		return;
	};
	if (c < (' ': u8) || c > ('~': u8)) {
		rt::print("  ");
		return;
	};
	rt::putc(c);
};

fn atcol(v: size) void = {
	let buf: [16]u8 = [0...];
	let i = len(buf);
	let x = v;
	for (let k = 0u64; k < 8 && x > 0; k += 1) {
		i -= 1;
		buf[i] = hexdig((x % 16): u8);
		x /= 16;
	};
	for (let k = i; k < 7; k += 1) {
		rt::putc(' ': u8);
	};
	rt::write(buf[i..]);
	rt::putc(' ': u8);
};

fn dump(text: []u8) void = {
	for (let at = 0z; at < len(text); at += WIDTH) {
		atcol(at);
		if (showoct) {
			for (let j = 0z; j < WIDTH && at + j < len(text); j += 1) {
				rt::print("00");
				rt::putc(hexdig(text[at + j] >> 3 & 7));
				rt::putc(hexdig(text[at + j] & 7));
				rt::putc(' ': u8);
			};
			rt::putc(' ': u8);
		};
		if (showhex) {
			for (let j = 0z; j < WIDTH && at + j < len(text); j += 1) {
				rt::putc(hexdig(text[at + j] >> 4));
				rt::putc(hexdig(text[at + j] & 0x0f));
				rt::putc(' ': u8);
			};
			for (let j = len(text) - at; j < WIDTH; j += 1) {
				rt::print("   ");
			};
			rt::putc(' ': u8);
		};
		if (showchar) {
			rt::putc('|': u8);
			for (let j = 0z; j < WIDTH && at + j < len(text); j += 1) {
				character(text[at + j]);
			};
			rt::putc('|': u8);
		};
		rt::println("");
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let given: size = 0;
	for (let k = 0z; pos < len(args); k += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('c': u8)) {
			showchar = true;
			showhex = false;
		} else if (len(tok) == 2 && tok[1] == ('o': u8)) {
			showoct = true;
			showhex = false;
		} else if (len(tok) == 2 && tok[1] == ('x': u8)) {
			showhex = true;
		} else if (tok[0] == ('-': u8)) {
			rt::print("od: unknown option ");
			rt::println(*(&tok: *str));
			return;
		} else {
			// The first thing that is not a flag is the file, and anything
			// after it is the offset to start at.
			break;
		};
		pos = lib::skip_space(args, pos + len(tok));
		given += 1;
	};

	const path = lib::arg_n(args, given);
	if (len(path) == 0) {
		let buf: [512]u8 = [0...];
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
		dump(buf[..n]);
		return;
	};

	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("od: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	// An offset past the end is not an error; it just has nothing to show,
	// which is quieter than refusing to say so.
	const at = lib::parse_int(lib::arg_n(args, 1), 0): size;
	const from = if (at < len(text)) at else len(text);
	dump(text[from..]);
	lib::release(text);
};