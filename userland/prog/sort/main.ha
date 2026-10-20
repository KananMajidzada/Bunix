use lib;
use rt;

// sort [-n] [-r] [file...]
//
// The lines of a file in order. Plain order compares bytes, -n compares the
// number each line starts with, and -r turns the result around. The order is
// stable, so lines that compare equal keep the order they were written in,
// which is what makes "sort | uniq -c" count runs the way a reader expects.
//
// Sorting moves the lines themselves rather than an index into them, so each
// one is held as an address and a length: every line points into the one
// buffer the file was read into.

def MAXLINES: size = 2048;
def MAXLINE: size = 512;

let lptr: [MAXLINES]uintptr = [0...];
let llen: [MAXLINES]size = [0...];
let nlines: size = 0;
let dropped: size = 0;
let numeric: bool = false;
let reverse: bool = false;

// A line longer than this is truncated rather than held whole. The filters
// that share this shape all have a stack and a table to fit inside, and a file
// with one enormous line in it should not be the reason they fail to run.
fn note(line: []u8) bool = {
	if (nlines >= MAXLINES) {
		dropped += 1;
		return true;
	};
	let l = line;
	if (len(l) > MAXLINE) {
		l = l[..MAXLINE];
		dropped += 1;
	};
	lptr[nlines: size] = lib::at_ptr(l);
	llen[nlines: size] = len(l);
	nlines += 1;
	return true;
};

fn line(i: size) []u8 = {
	return lib::view(lptr[i], llen[i]);
};

// The number a line begins with, for -n. Text without a leading number sorts
// as zero, which is what makes a list of measurements order itself.
fn numkey(b: []u8) u64 = {
	let v = 0u64;
	let seen = false;
	for (let i = 0z; i < len(b) && lib::is_digit(b[i]); i += 1) {
		v = v * 10 + (b[i] - ('0': u8): u64);
		seen = true;
	};
	if (!seen) {
		return 0;
	};
	return v;
};

fn less(a: []u8, b: []u8) bool = {
	if (numeric && (numkey(a) != numkey(b))) {
		return numkey(a) < numkey(b);
	};
	return compare(a, b) < 0;
};

fn compare(a: []u8, b: []u8) int = {
	const n = if (len(a) < len(b)) len(a) else len(b);
	for (let i = 0z; i < n; i += 1) {
		if (a[i] != b[i]) {
			return (a[i]: int) - (b[i]: int);
		};
	};
	return (len(a): int) - (len(b): int);
};

fn show(a: []u8) bool = {
	rt::write(a);
	rt::println("");
	return true;
};

fn sort_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("sort: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	nlines = 0;
	dropped = 0;
	lib::each_line(text, &note);

	// Insertion sort. It is the only one worth writing here: the table holds a
	// couple of thousand lines, the file is already whole in memory, and this
	// keeps the order of equal lines without any extra bookkeeping.
	for (let i = 1z; i < nlines; i += 1) {
		const p = lib::at_ptr(line(i));
		const l = llen[i];
		// Where the line being put in will end up. Each turn of the loop
		// closes the gap it just left by one, so the line belongs at k - 1
		// rather than at k: setting it to k is what pins the first line to
		// the front of the table whatever order the rest arrive in.
		let j = i;
		for (let k = i; k > 0 && less(lib::view(p, l), line(k - 1)); k -= 1) {
			j = k - 1;
			lptr[k] = lptr[k - 1];
			llen[k] = llen[k - 1];
		};
		lptr[j] = p;
		llen[j] = l;
	};

	if (reverse) {
		for (let i = 0z; i < nlines / 2; i += 1) {
			const j = nlines - 1 - i;
			const tp = lptr[i];
			const tl = llen[i];
			lptr[i] = lptr[j];
			llen[i] = llen[j];
			lptr[j] = tp;
			llen[j] = tl;
		};
	};

	for (let i = 0z; i < nlines; i += 1) {
		show(line(i));
	};
	if (dropped > 0) {
		rt::print("sort: ");
		rt::printnum(dropped: u64);
		rt::println(" lines did not fit");
	};
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('n': u8)) {
			numeric = true;
		} else if (len(tok) == 2 && tok[1] == ('r': u8)) {
			reverse = true;
		} else {
			rt::print("sort: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		pos = lib::skip_space(args, pos + len(tok));
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		sort_file(path);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: sort [-n] [-r] [file...]");
	};
};