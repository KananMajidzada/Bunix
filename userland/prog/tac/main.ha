use lib;
use rt;

// tac [file...]
//
// The lines of a file in the opposite order. rev turns a line around; this one
// leaves each line as it is and only moves it.

def MAXLINES: size = 2048;

let lptr: [MAXLINES]uintptr = [0...];
let llen: [MAXLINES]size = [0...];
let nlines: size = 0;
let dropped: size = 0;

fn note(line: []u8) bool = {
	if (nlines >= MAXLINES) {
		dropped += 1;
		return true;
	};
	lptr[nlines] = lib::at_ptr(line);
	llen[nlines] = lib::at_len(line);
	nlines += 1;
	return true;
};

fn tac_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("tac: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	nlines = 0;
	dropped = 0;
	lib::each_line(text, &note);
	for (let i = nlines; i > 0; i -= 1) {
		rt::write(lib::view(lptr[i - 1], llen[i - 1]));
		rt::println("");
	};
	if (dropped > 0) {
		rt::print("tac: ");
		rt::printnum(dropped: u64);
		rt::println(" lines did not fit");
	};
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
		tac_file(path);
		pos = next;
	};
};