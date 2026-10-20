use lib;
use rt;

// cut -d delim -f list [file...]
//
// Prints chosen fields of each line. The list is the usual one: a number, a
// run like 2-5, or both separated by commas. The delimiter is one byte and
// defaults to a tab, so cutting a listing that already uses tabs needs no
// flag at all.

def MAXSET: size = 64;

let lo: [MAXSET]size = [0...];
let hi: [MAXSET]size = [0...];
let nset: size = 0;
let delim: u8 = '\t';
let havefields: bool = false;
let none: []u8 = [];

// Parses "1,3-5" into the two tables. A run whose far end comes before its
// near end is taken the way it was written, so "5-2" prints fields five down
// to two rather than nothing at all.
fn add_run(spec: []u8) void = {
	if (len(spec) == 0 || nset >= MAXSET) {
		return;
	};
	const dash = lib::index_of(spec, '-': u8);
	if (dash < len(spec)) {
		lo[nset] = lib::parse_int(spec[..dash], 0): size;
		hi[nset] = lib::parse_int(spec[dash + 1..], 0): size;
	} else {
		lo[nset] = lib::parse_int(spec, 0): size;
		hi[nset] = lo[nset];
	};
	nset += 1;
};

fn add_list(spec: []u8) void = {
	let start = 0z;
	for (let i = 0z; i <= len(spec); i += 1) {
		if (i == len(spec) || spec[i] == (',': u8)) {
			add_run(spec[start..i]);
			start = i + 1;
		};
	};
};

fn wanted(f: size) bool = {
	for (let i = 0z; i < nset; i += 1) {
		if (f >= lo[i] && f <= hi[i]) {
			return true;
		};
	};
	return false;
};

// The value of a flag, taken either from the rest of this token or from the
// next one, along with where the line should carry on from. This is what makes
// both "-f1,3" and "-f 1,3" work, which between them cover how anyone writes
// it.
fn optval(args: []u8, pos: size, width: size) ([]u8, size) = {
	const tok = args[pos..lib::token_end(args, pos)];
	if (len(tok) > width) {
		return (tok[width..], lib::skip_space(args, pos + len(tok)));
	};
	const after = lib::skip_space(args, pos + width);
	if (after >= len(args)) {
		return (none, pos);
	};
	return lib::next_arg(args, after);
};

// Fields are numbered from one. A field that never appears in a line is simply
// not printed, so lines of different shapes can go through one cut together.
fn show(line: []u8) bool = {
	let f: size = 1;
	let start = 0z;
	let first = true;
	for (let i = 0z; i <= len(line); i += 1) {
		if (i < len(line) && line[i] != delim) {
			continue;
		};
		if (wanted(f)) {
			if (!first) {
				rt::putc(delim);
			};
			rt::write(line[start..i]);
			first = false;
		};
		f += 1;
		start = i + 1;
	};
	rt::println("");
	return true;
};

fn cut_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("cut: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	lib::each_line(text, &show);
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) > 1 && (tok[1] == ('d': u8) || tok[1] == ('f': u8))) {
			let (val, next) = optval(args, pos, 2);
			if (len(val) == 0) {
				rt::print("cut: -");
				rt::putc(tok[1]);
				rt::println(" wants a value");
				return;
			};
			if (tok[1] == ('d': u8)) {
				delim = val[0];
			} else {
				add_list(val);
				havefields = true;
			};
			pos = next;
			continue;
		};
		rt::print("cut: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	if (!havefields) {
		rt::println("usage: cut -d delim -f list [file...]");
		return;
	};

	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		cut_file(path);
		pos = next;
	};
};