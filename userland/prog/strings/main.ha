use lib;
use rt;

// strings [-n min] [file...]
//
// The runs of printable bytes in a file. A program or an archive is mostly
// things no reader wants to look at, and the handful of names and messages
// inside it are what this is for: which is how a linker or a compiler binary
// gets searched without a text editor. hd shows the bytes; this shows the
// text.

let least: size = 4;
let run: [MAXRUN]u8 = [0...];
let runlen: size = 0;

def MAXRUN: size = 256;

fn flush() void = {
	if (runlen >= least) {
		rt::write(run[..runlen]);
		rt::println("");
	};
	runlen = 0;
};

fn strings_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("strings: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	runlen = 0;
	for (let i = 0z; i < len(text); i += 1) {
		const c = text[i];
		if (lib::is_print(c)) {
			// A run longer than the buffer is still worth reporting, so the
			// first of it is written rather than the tail being lost.
			if (runlen == len(run)) {
				flush();
			};
			run[runlen] = c;
			runlen += 1;
		} else {
			flush();
		};
	};
	flush();
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) > 1 && tok[1] == ('n': u8)) {
			let (v, next) = lib::flag_val(args, pos, 2, least: u64);
			least = v: size;
			pos = next;
			continue;
		};
		rt::print("strings: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		strings_file(path);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: strings [-n min] [file...]");
	};
};