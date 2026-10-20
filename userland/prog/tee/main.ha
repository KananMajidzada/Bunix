use lib;
use rt;

// tee [-a] file...
//
// Reads lines and writes them to every file named as well as to the screen, so
// a program whose output you want to look at and keep at once can be run
// without changing what it does. Ctrl-D on an empty line ends the input.
//
// There is no way to pipe one command into another here: a program either
// reads the keyboard or reads a file, and there are no pipes in the kernel to
// join them up. What tee gives is the other half of that, which is keeping a
// copy of something you have just watched go past.

def MAXFILES: size = 8;

let paths: [MAXFILES][]u8 = [[]...];
let adding: bool = false;

def LINECAP: size = 512;
let line: [LINECAP]u8 = [0...];

// One place the line goes out to, so the keyboard echo, the files and the
// screen all show the same thing.
fn emit(b: []u8) void = {
	for (let i = 0z; i < len(paths); i += 1) {
		// The kernel's write replaces a file whole, so appending means
		// carrying the old bytes along with the new ones.
		if (adding) {
			append_one(paths[i], b);
		} else {
			_ = rt::writefile(*(&paths[i]: *str), b);
		};
	};
	rt::write(b);
	rt::println("");
};

fn append_one(path: []u8, b: []u8) void = {
	let old = lib::slurp(path);
	let mem = rt::malloc(len(old) + len(b) + 1);
	const addr = match (mem) {
	case null =>
		return;
	case let q: *opaque =>
		yield q: uintptr;
	};
	const all = lib::view(addr, len(old) + len(b) + 1);
	for (let i = 0z; i < len(old); i += 1) {
		all[i] = old[i];
	};
	for (let i = 0z; i < len(b); i += 1) {
		all[len(old) + i] = b[i];
	};
	_ = rt::writefile(*(&path: *str), all[..len(old) + len(b)]);
	if (len(old) > 0) {
		lib::release(old);
	};
	rt::free_(addr: *opaque);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('a': u8)) {
			adding = true;
			pos = lib::skip_space(args, pos + len(tok));
			continue;
		};
		rt::print("tee: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (nfiles < MAXFILES) {
			paths[nfiles] = path;
		};
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: tee [-a] file...");
		return;
	};

	for (true) {
		let n = 0z;
		for (true) {
			const c = rt::getchar();
			if (c == 3) {
				return;
			};
			if (c == 4) {
				if (n > 0) {
					emit(line[..n]);
				};
				return;
			};
			if (c == ('\n': u8)) {
				break;
			};
			if (c == 8 || c == 127) {
				if (n > 0) {
					n -= 1;
					rt::print("\b \b");
				};
				continue;
			};
			if (n < len(line)) {
				line[n] = c;
				n += 1;
				rt::putc(c);
			};
		};
		emit(line[..n]);
	};
};