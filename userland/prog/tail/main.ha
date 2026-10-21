use lib;
use rt;

const N_FLAG: str = "-n";

def MAXLINES: size = 1024;

// Prints the last lines of a file. By default ten of them.
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
		// The number of lines can be put right after the dash.
		if (len(w) > 1 && w[0] == ('-': u8)
				&& w[1] >= ('0': u8) && w[1] <= ('9': u8)) {
			let v: u64 = 0;
			if (lib::number(w[1..], &v) > 0) {
				count = v;
				continue;
			};
		};
		if (lib::str_eq(w, *(&N_FLAG: *[]u8))) {
			if (i + 1 >= n) {
				rt::println("usage: tail [-n count] <path>");
				return;
			};
			i += 1;
			let v: u64 = 0;
			if (lib::number(words[i], &v) == 0) {
				rt::println("tail: not a number");
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
		rt::println("usage: tail [-n count] <path>");
		return;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("tail: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("tail: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	// The lines are kept in a ring, so only the last few are held and the
	// rest of the file can be read in one go.
	let rstart: [MAXLINES]size = [0...];
	let rlen: [MAXLINES]size = [0...];
	let rpos = 0z;
	let rn = 0z;
	let cap = if (count < (MAXLINES: u64)) (count: size) else MAXLINES;
	if (cap == 0) {
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			rstart[rpos] = start;
			rlen[rpos] = i - start;
			rpos = (rpos + 1) % cap;
			if (rn < cap) {
				rn += 1;
			};
			start = i + 1;
		};
	};
	// The oldest line is the one the ring is about to write over.
	const first: size = if (rn == cap) rpos else 0z;
	for (let k = 0z; k < rn; k += 1) {
		const idx = (first + k) % cap;
		rt::write(buf[rstart[idx]..rstart[idx] + rlen[idx]]);
		rt::println("");
	};
};
