use lib;
use rt;

def MAXLINES: size = 512;

// The lines two files have in common. Only the lines that are in both are
// printed, and they are printed in the order the first file has them.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 2) {
		rt::println("usage: comm <path> <path>");
		return;
	};
	const w1 = rt::page_alloc(4);
	const w2 = rt::page_alloc(4);
	if (w1 == 0 || w2 == 0) {
		rt::println("comm: out of memory");
		return;
	};
	const first = read_file(words[0], (w1: *[16384]u8)[..], &s1, &e1);
	const second = read_file(words[1], (w2: *[16384]u8)[..], &s2, &e2);
	if (first.count == 0 || second.count == 0) {
		rt::println("comm: cannot read the files");
		return;
	};
	for (let l = 0z; l < first.count; l += 1) {
		const text = first.buf[first.starts[l]..first.ends[l]];
		for (let j = 0z; j < second.count; j += 1) {
			const other = second.buf[second.starts[j]..second.ends[j]];
			if (same(text, other)) {
				rt::write(text);
				rt::println("");
				break;
			};
		};
	};
};

// A file read into memory, with its lines found. The tables of where the
// lines are are kept apart from the file itself, so that a file does not
// have to be copied about.
type file = struct {
	buf: []u8,
	starts: *[MAXLINES]size,
	ends: *[MAXLINES]size,
	count: size,
};

let s1: [MAXLINES]size = [0...];
let e1: [MAXLINES]size = [0...];
let s2: [MAXLINES]size = [0...];
let e2: [MAXLINES]size = [0...];

// Reads a file and finds its lines.
fn read_file(
	path: []u8,
	buf: []u8,
	starts: *[MAXLINES]size,
	ends: *[MAXLINES]size,
) file = {
	let f = file { buf = buf, starts = starts, ends = ends, count = 0 };
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		return f;
	};
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			if (f.count < MAXLINES) {
				f.starts[f.count] = start;
				f.ends[f.count] = i;
				f.count += 1;
			};
			start = i + 1;
		};
	};
	return f;
};

// Whether two sets of bytes are the same.
fn same(a: []u8, b: []u8) bool = {
	if (len(a) != len(b)) {
		return false;
	};
	for (let i = 0z; i < len(a); i += 1) {
		if (a[i] != b[i]) {
			return false;
		};
	};
	return true;
};
