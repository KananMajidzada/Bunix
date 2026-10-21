use lib;
use rt;

def MAXLINES: size = 512;

// The lines two files have in common, and the lines they do not. The first
// column is the lines only the first file has, the second is the lines only
// the second has, and the third is the lines both have. The files are
// expected to be sorted. -1, -2 and -3 leave out a column.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let paths: [2][]u8 = [[]...];
	let npath = 0z;
	let show1 = true;
	let show2 = true;
	let show3 = true;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (len(w) > 1 && w[0] == ('-': u8)) {
			// More than one column can be left out in the same word.
			let ok = true;
			for (let j = 1z; j < len(w); j += 1) {
				if (w[j] == ('1': u8)) {
					show1 = false;
				} else if (w[j] == ('2': u8)) {
					show2 = false;
				} else if (w[j] == ('3': u8)) {
					show3 = false;
				} else {
					ok = false;
				};
			};
			if (ok) {
				continue;
			};
		};
		if (npath < 2) {
			paths[npath] = w;
			npath += 1;
		};
	};
	if (npath < 2) {
		rt::println("usage: comm [-1] [-2] [-3] <path> <path>");
		return;
	};
	const w1 = rt::page_alloc(4);
	const w2 = rt::page_alloc(4);
	if (w1 == 0 || w2 == 0) {
		rt::println("comm: out of memory");
		return;
	};
	const first = read_file(paths[0], (w1: *[16384]u8)[..], &s1, &e1);
	const second = read_file(paths[1], (w2: *[16384]u8)[..], &s2, &e2);
	if (first.count == 0 || second.count == 0) {
		rt::println("comm: cannot read the files");
		return;
	};
	// The two files are walked together, a line at a time, so that each
	// line is put in the column it belongs in.
	let i = 0z;
	let j = 0z;
	for (i < first.count || j < second.count) {
		let line: []u8 = first.buf[0..0];
		let col = 1;
		if (i >= first.count) {
			col = 2;
			line = second.buf[second.starts[j]..second.ends[j]];
		} else if (j >= second.count) {
			line = first.buf[first.starts[i]..first.ends[i]];
		} else {
			const x = first.buf[first.starts[i]..first.ends[i]];
			const y = second.buf[second.starts[j]..second.ends[j]];
			if (same(x, y)) {
				col = 3;
				line = x;
			} else if (less(x, y)) {
				line = x;
			} else {
				col = 2;
				line = y;
			};
		};
		if (col == 1) {
			if (show1) {
				rt::write(line);
				rt::println("");
			};
			i += 1;
		} else if (col == 2) {
			if (show2) {
				rt::putc(('\t': u8));
				rt::write(line);
				rt::println("");
			};
			j += 1;
		} else {
			if (show3) {
				rt::putc(('\t': u8));
				rt::putc(('\t': u8));
				rt::write(line);
				rt::println("");
			};
			i += 1;
			j += 1;
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

// Whether one line comes before another, the way a sorting of the lines
// would put them.
fn less(a: []u8, b: []u8) bool = {
	let n = len(a);
	if (len(b) < n) {
		n = len(b);
	};
	for (let i = 0z; i < n; i += 1) {
		if (a[i] != b[i]) {
			return a[i] < b[i];
		};
	};
	return len(a) < len(b);
};
