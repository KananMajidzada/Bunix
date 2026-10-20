use lib;
use rt;

// uniq [-c] [-d] [file...]
//
// Drops the lines that repeat the one before them. This is the other half of
// sort: a sorted file turned through uniq shows what repeats and how often.
// -c puts a count in front of each line, and -d keeps only the lines that
// repeat, which is the same thing as asking for a count above one.

let count: bool = false;
let onlydup: bool = false;

let prev: [MAXLINE]u8 = [0...];
let prevlen: size = 0;
let run: u64 = 0;
let shown: u64 = 0;

def MAXLINE: size = 512;

// Emits the run that has just ended, if it is one the flags asked for.
fn flush() void = {
	if (prevlen == 0) {
		return;
	};
	if (!onlydup || run > 1) {
		shown += 1;
		if (count) {
			rt::printnum(run);
			rt::print(" ");
		};
		rt::write(prev[..prevlen]);
		rt::println("");
	};
	run = 0;
	prevlen = 0;
};

fn note(line: []u8) bool = {
	// A trailing blank is not part of the line's identity, so "a" and "a "
	// are the same line as far as a reader is concerned.
	const l = lib::rtrim(line);
	if (len(l) == prevlen && lib::str_eq(l, prev[..prevlen])) {
		run += 1;
		return true;
	};
	flush();
	const take = if (len(l) > len(prev)) len(prev) else len(l);
	for (let i = 0z; i < take; i += 1) {
		prev[i] = l[i];
	};
	prevlen = take;
	run = 1;
	return true;
};

fn uniq_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("uniq: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	prevlen = 0;
	run = 0;
	lib::each_line(text, &note);
	flush();
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('c': u8)) {
			count = true;
		} else if (len(tok) == 2 && tok[1] == ('d': u8)) {
			onlydup = true;
		} else {
			rt::print("uniq: unknown option ");
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
		uniq_file(path);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: uniq [-c] [-d] [file...]");
	};
};