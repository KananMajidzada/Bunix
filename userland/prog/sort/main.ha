use lib;
use rt;

def MAXLINES: size = 1024;

type line = struct {
	off: size,
	ln: size,
};

// Sorts the lines of a file.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: sort <path>");
		return;
	};
	const path = words[0];
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
	for (let i = 0z; i < nl; i += 1) {
		rt::write(buf[lines[i].off..lines[i].off + lines[i].ln]);
		rt::println("");
	};
};

// Whether one line comes before another.
fn less(buf: []u8, a: *line, b: *line) bool = {
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
