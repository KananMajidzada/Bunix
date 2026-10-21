use lib;
use rt;

// Turns each line of a file upside down.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: rev <path>");
		return;
	};
	const path = words[0];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("rev: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("rev: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			for (let j = i; j > start; j -= 1) {
				rt::putc(buf[j - 1]);
			};
			rt::println("");
			start = i + 1;
		};
	};
};
