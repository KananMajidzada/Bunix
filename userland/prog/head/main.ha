use lib;
use rt;

const N_FLAG: str = "-n";

// Prints the first lines of a file. By default ten of them.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let count: u64 = 10;
	let path: []u8 = words[0][0..0];
	let have = false;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (lib::str_eq(w, *(&N_FLAG: *[]u8))) {
			// The number of lines comes next.
			if (i + 1 >= n) {
				rt::println("usage: head [-n count] <path>");
				return;
			};
			i += 1;
			let v: u64 = 0;
			if (lib::number(words[i], &v) == 0) {
				rt::println("head: not a number");
				return;
			};
			count = v;
			continue;
		};
		if (!have) {
			path = w;
			have = true;
		};
	};
	if (!have) {
		rt::println("usage: head [-n count] <path>");
		return;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("head: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("head: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let lines: u64 = 0;
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			if (lines >= count) {
				break;
			};
			rt::write(buf[start..i]);
			rt::println("");
			lines += 1;
			start = i + 1;
		};
	};
};
