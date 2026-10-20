use lib;
use rt;

// nl [-w width] [file...]
//
// Numbers the lines of a file. The number sits in a field wide enough for the
// largest one, so the text that follows lines up and a listing can be read
// across. A line with no newline at the end still gets a number.

let width: size = 6;
let n: u64 = 1;

fn pad(v: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	let x = v;
	for (let k = 0z; k < 20 && x > 0; k += 1) {
		i -= 1;
		buf[i] = ((x % 10): u8) + ('0': u8);
		x /= 10;
	};
	rt::write(buf[i..]);
	for (let k = i; k < width; k += 1) {
		rt::putc(' ': u8);
	};
	rt::putc('\t': u8);
};

fn note(line: []u8) bool = {
	pad(n);
	rt::write(line);
	rt::println("");
	n += 1;
	return true;
};

fn nl_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("nl: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	n = 1;
	lib::each_line(text, &note);
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) > 1 && tok[1] == ('w': u8)) {
			let (v, next) = lib::flag_val(args, pos, 2, width: u64);
			width = v: size;
			pos = next;
			continue;
		};
		rt::print("nl: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		nl_file(path);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: nl [-w width] [file...]");
	};
};