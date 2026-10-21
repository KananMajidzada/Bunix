use lib;
use rt;

// Numbers the lines of a file.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: nl <path>");
		return;
	};
	const path = words[0];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("nl: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("nl: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let number: u64 = 0;
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			number += 1;
			// The number is padded out so the lines line up.
			let pad = 0z;
			let v = number;
			for (v > 0) {
				pad += 1;
				v /= 10;
			};
			for (let k = pad; k < 6; k += 1) {
				rt::putc(' ');
			};
			rt::printnum(number);
			rt::putc('\t');
			rt::write(buf[start..i]);
			rt::println("");
			start = i + 1;
		};
	};
};
