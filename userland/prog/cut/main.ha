use lib;
use rt;

const D_FLAG: str = "-d";
const F_FLAG: str = "-f";

// Cuts parts out of each line. "cut -d: -f2 file" takes the second field of
// every line, where the fields are separated by a colon. A field may be
// given as a number, as a range of numbers, or as a list of both.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let delim: u8 = '\t': u8;
	let fields: []u8 = words[0][0..0];
	let path: []u8 = words[0][0..0];
	let have = false;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (lib::str_eq(w, *(&D_FLAG: *[]u8))) {
			if (i + 1 >= n) {
				rt::println("usage: cut -d <char> -f <fields> <path>");
				return;
			};
			i += 1;
			delim = words[i][0];
			continue;
		};
		if (lib::str_eq(w, *(&F_FLAG: *[]u8))) {
			if (i + 1 >= n) {
				rt::println("usage: cut -d <char> -f <fields> <path>");
				return;
			};
			i += 1;
			fields = words[i];
			continue;
		};
		if (!have) {
			path = w;
			have = true;
		};
	};
	if (!have || len(fields) == 0) {
		rt::println("usage: cut -d <char> -f <fields> <path>");
		return;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("cut: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("cut: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			cut_line(buf[start..i], delim, fields);
			rt::println("");
			start = i + 1;
		};
	};
};

// The fields of one line that were asked for, separated by the delimiter.
fn cut_line(line: []u8, delim: u8, fields: []u8) void = {
	// The fields of the line, and where each one ends.
	let starts: [64]size = [0...];
	let ends: [64]size = [0...];
	let count = 0z;
	let pos = 0z;
	for (true) {
		if (count >= 64) {
			break;
		};
		starts[count] = pos;
		let end = pos;
		for (end < len(line) && line[end] != delim) {
			end += 1;
		};
		ends[count] = end;
		count += 1;
		if (end >= len(line)) {
			break;
		};
		pos = end + 1;
	};
	// The list of fields is walked, and each one that was asked for is
	// printed.
	let i = 0z;
	let first = true;
	for (i < len(fields)) {
		// A number, or a range of them.
		let lo: u64 = 0;
		let hi: u64 = 0;
		let got = lib::number(fields[i..], &lo);
		if (got == 0) {
			i += 1;
			continue;
		};
		i += got;
		hi = lo;
		if (i < len(fields) && fields[i] == ('-': u8)) {
			i += 1;
			let got2 = lib::number(fields[i..], &hi);
			if (got2 == 0) {
				hi = lo;
			} else {
				i += got2;
			};
		};
		for (let f = lo; f <= hi; f += 1) {
			if (f < 1 || f > (count: u64)) {
				continue;
			};
			const k = (f - 1): size;
			if (!first) {
				rt::putc(delim);
			};
			first = false;
			rt::write(line[starts[k]..ends[k]]);
		};
	};
};
