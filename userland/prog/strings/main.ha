use lib;
use rt;

// Prints the runs of printable characters in a file. A run has to be at
// least four characters long to be worth showing.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: strings <path>");
		return;
	};
	const path = words[0];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("strings: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("strings: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		const printable = i < flen && buf[i] >= (' ': u8) && buf[i] < 0x7F;
		if (printable) {
			continue;
		};
		// The run of printable characters has come to an end.
		if (i - start >= 4) {
			rt::write(buf[start..i]);
			rt::println("");
		};
		start = i + 1;
	};
};
