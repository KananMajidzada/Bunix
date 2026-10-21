use lib;
use rt;

// Dumps a file in octal and in hex, the way od does. The offsets are shown
// every sixteen bytes.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: od <path>");
		return;
	};
	const path = words[0];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("od: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("od: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	for (let i = 0z; i < flen; i += 16) {
		// The offset of the line, in octal.
		rt::printnum((i: u64) / 8);
		rt::print(" ");
		for (let j = 0z; j < 16; j += 1) {
			if (i + j < flen) {
				const b = buf[i + j];
				rt::printnum((b: u64) / 64);
				rt::putc('0' + ((b / 8) & 7));
				rt::putc('0' + (b & 7));
			} else {
				rt::print("   ");
			};
			rt::putc(' ');
		};
		rt::print("  ");
		for (let j = 0z; j < 16 && i + j < flen; j += 1) {
			const b = buf[i + j];
			rt::putc(hexdig(b >> 4));
			rt::putc(hexdig(b & 15));
			rt::putc(' ');
		};
		rt::println("");
	};
};

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};
