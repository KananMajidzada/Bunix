use lib;
use rt;

const D_FLAG: str = "-d";

// Translates characters in a file. "tr abc xyz" turns a into x, b into y
// and c into z. With -d the characters in the first set are dropped instead.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let del = false;
	let pos: [4][]u8 = [[]...];
	let npos = 0z;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (lib::str_eq(w, *(&D_FLAG: *[]u8))) {
			del = true;
			continue;
		};
		if (npos < 4) {
			pos[npos] = w;
			npos += 1;
		};
	};
	if (npos < 3) {
		rt::println("usage: tr [-d] <set> <set> <path>");
		return;
	};
	const from = pos[0];
	const to = pos[1];
	const file = pos[2];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("tr: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&file: *str), buf);
	if (flen == 0) {
		rt::print("tr: cannot read ");
		rt::println(*(&file: *str));
		return;
	};
	for (let i = 0z; i < flen; i += 1) {
		const c = buf[i];
		const idx = index_of(from, c);
		if (idx < 0) {
			rt::putc(c);
			continue;
		};
		if (del) {
			continue;
		};
		if ((idx: size) < len(to)) {
			rt::putc(to[idx]);
		};
	};
};

// Where a character is in a set, or -1 when it is not there.
fn index_of(set: []u8, c: u8) int = {
	for (let i = 0z; i < len(set); i += 1) {
		if (set[i] == c) {
			return i: int;
		};
	};
	return -1;
};
