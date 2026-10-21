use lib;
use rt;

def MAXLINES: size = 1024;

type line = struct {
	off: size,
	ln: size,
};

let numeric = false;
let reverse = false;
let unique = false;

// Sorts the lines of a file. With -n the lines are sorted by the number
// they begin with, with -r the order is turned around, and with -u a line
// that is the same as the one before it is left out.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let path: []u8 = words[0][0..0];
	let have = false;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (len(w) > 1 && w[0] == ('-': u8)) {
			let ok = true;
			for (let j = 1z; j < len(w); j += 1) {
				if (w[j] == ('n': u8)) {
					numeric = true;
				} else if (w[j] == ('r': u8)) {
					reverse = true;
				} else if (w[j] == ('u': u8)) {
					unique = true;
				} else {
					ok = false;
				};
			};
			if (ok) {
				continue;
			};
		};
		if (!have) {
			path = w;
			have = true;
		};
	};
	if (!have) {
		rt::println("usage: sort [-nru] <path>");
		return;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("sort: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("sort: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let lines: [MAXLINES]line = [line { off = 0, ln = 0 }...];
	let nl = 0z;
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			if (nl < MAXLINES) {
				lines[nl] = line { off = start, ln = i - start };
				nl += 1;
			};
			start = i + 1;
		};
	};
	// An insertion sort: the lists here are short, and it keeps the order
	// of equal lines as they were.
	for (let i = 1z; i < nl; i += 1) {
		const t = lines[i];
		let j = i;
		for (j > 0 && less(buf, &t, &lines[j - 1])) {
			lines[j] = lines[j - 1];
			j -= 1;
		};
		lines[j] = t;
	};
	for (let k = 0z; k < nl; k += 1) {
		// A turned around sorting is the same list read the other way.
		const i = if (reverse) nl - 1 - k else k;
		if (unique && k > 0) {
			const prev = if (reverse) i + 1 else i - 1;
			if (same(buf, &lines[i], &lines[prev])) {
				continue;
			};
		};
		rt::write(buf[lines[i].off..lines[i].off + lines[i].ln]);
		rt::println("");
	};
};

// Whether one line comes before another.
fn less(buf: []u8, a: *line, b: *line) bool = {
	// A sorting by value looks at the number the line begins with, and
	// only falls back on the text when the numbers are the same.
	if (numeric) {
		const x = number(buf[a.off..a.off + a.ln]);
		const y = number(buf[b.off..b.off + b.ln]);
		if (x != y) {
			return x < y;
		};
	};
	const n = if (a.ln < b.ln) a.ln else b.ln;
	for (let i = 0z; i < n; i += 1) {
		const x = buf[a.off + i];
		const y = buf[b.off + i];
		if (x != y) {
			return x < y;
		};
	};
	return a.ln < b.ln;
};

// Whether two lines are the same.
fn same(buf: []u8, a: *line, b: *line) bool = {
	if (a.ln != b.ln) {
		return false;
	};
	for (let i = 0z; i < a.ln; i += 1) {
		if (buf[a.off + i] != buf[b.off + i]) {
			return false;
		};
	};
	return true;
};

// The number a line begins with. A line that does not begin with one is
// taken to be zero, so it sorts with the other lines that are not numbers.
fn number(b: []u8) i64 = {
	let i = 0z;
	let neg = false;
	if (i < len(b) && (b[i] == ('-': u8) || b[i] == ('+': u8))) {
		neg = b[i] == ('-': u8);
		i += 1;
	};
	let v: i64 = 0;
	for (i < len(b) && b[i] >= ('0': u8) && b[i] <= ('9': u8)) {
		v = v * 10 + ((b[i] - ('0': u8)): i64);
		i += 1;
	};
	if (neg) {
		return -v;
	};
	return v;
};
