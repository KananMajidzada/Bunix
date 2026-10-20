use lib;
use rt;

// rev [file...]
//
// Turns each line back to front. tac is the other half of this: that one
// turns the order of the lines around, this one leaves the order alone.

fn show(line: []u8) bool = {
	for (let i = len(line); i > 0; i -= 1) {
		rt::putc(line[i - 1]);
	};
	rt::println("");
	return true;
};

fn rev_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("rev: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	lib::each_line(text, &show);
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		rev_file(path);
		pos = next;
	};
};