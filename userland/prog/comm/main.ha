use lib;
use rt;

// comm [-123] a b
//
// The lines two files have between them. The files are expected to be sorted,
// because that is the only thing that lets it work in one pass over each: the
// first line they both have is the same line, so once they part company there
// is nothing to look back at.
//
// All three columns come out in the order the lines sort rather than grouped
// by which column they are in, and a line is put where it belongs by the tabs
// in front of it. -1 drops the lines only the first file has, -2 the ones only
// the second, and -3 the ones they share.

def MAXLINES: size = 2048;

let al: [MAXLINES][]u8 = [[]...];
let bl: [MAXLINES][]u8 = [[]...];
let na: size = 0;
let nb: size = 0;
let dropped: size = 0;

let skip1: bool = false;
let skip2: bool = false;
let skip3: bool = false;

fn take(l: []u8) bool = {
	if (na >= MAXLINES) {
		dropped += 1;
		return true;
	};
	al[na] = l;
	na += 1;
	return true;
};

fn put(l: []u8) bool = {
	if (nb >= MAXLINES) {
		dropped += 1;
		return true;
	};
	bl[nb] = l;
	nb += 1;
	return true;
};

// Which column a line is in, out of the three comm prints: zero for a line
// only the first file has, one for one only the second has, and two for one
// they share.
//
// A column is put where it belongs by counting the tabs for the columns that
// are being printed before it, and a suppressed column leaves no gap at all,
// so what is printed closes up to the left behind it. That is the whole
// reason to ask for one column rather than all three.
fn marked(col: size, from: []u8) void = {
	let tabs = 0z;
	if (!skip1 && col > 0) {
		tabs += 1;
	};
	if (!skip2 && col > 1) {
		tabs += 1;
	};
	if (!skip3 && col > 2) {
		tabs += 1;
	};
	for (let i = 0z; i < tabs; i += 1) {
		rt::putc('\t': u8);
	};
	rt::println(*(&from: *str));
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

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let k = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; k += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) < 2) {
			rt::print("comm: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		for (let j = 1z; j < len(tok); j += 1) {
			if (tok[j] == ('1': u8)) {
				skip1 = true;
			} else if (tok[j] == ('2': u8)) {
				skip2 = true;
			} else if (tok[j] == ('3': u8)) {
				skip3 = true;
			} else {
				rt::print("comm: unknown option ");
				rt::println(*(&tok: *str));
				return;
			};
		};
		pos = lib::skip_space(args, pos + len(tok));
	};

	// The flags came off the front, so the two files are whatever is left.
	let names: [2][]u8 = [empty, empty];
	let n = 0z;
	for (let k = 0z; pos < len(args) && n < 2; k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		pos = next;
		names[n] = path;
		n += 1;
	};
	if (n < 2) {
		rt::println("usage: comm [-123] <file> <file>");
		return;
	};

	const a = lib::slurp(names[0]);
	const b = lib::slurp(names[1]);
	if (len(a) == 0 || len(b) == 0) {
		rt::println("comm: cannot read both files");
		if (len(a) > 0) {
			lib::release(a);
		};
		if (len(b) > 0) {
			lib::release(b);
		};
		return;
	};
	na = 0;
	nb = 0;
	dropped = 0;
	lib::each_line(a, &take);
	lib::each_line(b, &put);
	lib::release(a);
	lib::release(b);

	let i = 0z;
	let j = 0z;
	for (let step = 0z; step < MAXLINES * 2; step += 1) {
		if (i >= na || j >= nb) {
			break;
		};
		const c = compare(al[i], bl[j]);
		if (c == 0) {
			if (!skip3) {
				marked(2, al[i]);
			};
			i += 1;
			j += 1;
			continue;
		};
		// Whichever line sorts first cannot turn up further along in the
		// other file, so it belongs to that one alone. That is the whole of
		// it, and it is why the two have to be sorted.
		if (c < 0) {
			if (!skip1) {
				marked(0, al[i]);
			};
			i += 1;
			continue;
		};
		if (!skip2) {
			marked(1, bl[j]);
		};
		j += 1;
	};
	// Whatever is left of either file is the rest of that file alone.
	for (let k = i; k < na; k += 1) {
		if (!skip1) {
			marked(0, al[k]);
		};
	};
	for (let k = j; k < nb; k += 1) {
		if (!skip2) {
			marked(1, bl[k]);
		};
	};
	if (dropped > 0) {
		rt::print("comm: ");
		rt::printnum(dropped: u64);
		rt::println(" lines did not fit");
	};
};

let empty: []u8 = [];