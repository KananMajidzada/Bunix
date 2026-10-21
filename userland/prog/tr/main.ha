use lib;
use rt;

const D_FLAG: str = "-d";

// Translates characters in a file. "tr abc xyz" turns a into x, b into y
// and c into z. With -d the characters in the first set are dropped instead.
// A set can hold a range, as in "a-z", which stands for every character
// from the first to the second.
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
	if (npos < 3 && !(del && npos == 2)) {
		rt::println("usage: tr [-d] <set> [<set>] <path>");
		return;
	};
	// The sets are put out in full, so that a range in one of them is
	// matched against the same range in the other one. With -d there is
	// only one set, and the characters in it are dropped.
	let frombuf: [256]u8 = [0...];
	let tobuf: [256]u8 = [0...];
	const nfrom = expand(pos[0], &frombuf);
	let nto = 0z;
	if (!del) {
		nto = expand(pos[1], &tobuf);
	};
	const file = if (del) pos[1] else pos[2];
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
		const idx = index_of(frombuf[..nfrom], c);
		if (idx < 0) {
			rt::putc(c);
			continue;
		};
		if (del) {
			continue;
		};
		if ((idx: size) < nto) {
			rt::putc(tobuf[idx]);
		};
	};
};

// A set with the ranges in it put out in full, and how many characters it
// has then.
fn expand(set: []u8, out: *[256]u8) size = {
	let n = 0z;
	let i = 0z;
	for (i < len(set)) {
		// A range is a character, a dash, and a character after it.
		if (i + 2 < len(set) && set[i + 1] == ('-': u8)
				&& set[i + 2] > set[i]) {
			let c = (set[i]: u32);
			const last = (set[i + 2]: u32);
			for (c <= last) {
				if (n < 256) {
					out[n] = c: u8;
					n += 1;
				};
				c += 1;
			};
			i += 3;
			continue;
		};
		if (n < 256) {
			out[n] = set[i];
			n += 1;
		};
		i += 1;
	};
	return n;
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
