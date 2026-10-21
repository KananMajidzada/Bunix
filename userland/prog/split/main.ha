use lib;
use rt;

// Splits a file into pieces of a given number of lines. The pieces are
// named after the file, with a letter on the end, unless a name to put in
// front of the letters is given.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: split [-l lines] <path> [prefix]");
		return;
	};
	let per: u64 = 1000;
	let path: []u8 = words[0][0..0];
	let prefix: []u8 = words[0][0..0];
	let have = false;
	let haveprefix = false;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (lib::str_eq(w, *(&"-l": *[]u8))) {
			if (i + 1 >= n) {
				rt::println("usage: split [-l lines] <path> [prefix]");
				return;
			};
			i += 1;
			let v: u64 = 0;
			if (lib::number(words[i], &v) == 0 || v == 0) {
				rt::println("split: not a number of lines");
				return;
			};
			per = v;
			continue;
		};
		if (!have) {
			path = w;
			have = true;
			continue;
		};
		// The word after the file is the name the pieces are given.
		if (!haveprefix) {
			prefix = w;
			haveprefix = true;
		};
	};
	if (!have) {
		rt::println("usage: split [-l lines] <path> [prefix]");
		return;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("split: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("split: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	// The name of a piece: the name that was asked for, or the name of the
	// file, and a letter on the end.
	let name: [64]u8 = [0...];
	let nl = 0z;
	const base = if (haveprefix) prefix else path;
	for (let i = 0z; i < len(base) && nl + 2 < len(name); i += 1) {
		name[nl] = base[i];
		nl += 1;
	};
	// The lines are counted, and a piece is written every so often.
	let lines: u64 = 0;
	let piece: u64 = 0;
	let start = 0z;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			lines += 1;
			if (lines == per) {
				write_piece(name[..nl], piece, buf[start..i]);
				piece += 1;
				lines = 0;
				start = i + 1;
			};
		};
	};
	// Whatever is left over is a piece of its own.
	if (start < flen) {
		write_piece(name, piece, buf[start..flen]);
		piece += 1;
	};
	rt::print("split into ");
	rt::printnum(piece);
	rt::println(" pieces");
};

// One piece of the file, written out.
fn write_piece(name: []u8, piece: u64, text: []u8) void = {
	let path: [80]u8 = [0...];
	let n = 0z;
	for (let i = 0z; i < len(name) && n + 2 < len(path); i += 1) {
		path[n] = name[i];
		n += 1;
	};
	// The letter on the end: a, b, c and so on, then aa and the rest.
	const letter = 'a' + (piece % 26): u8;
	path[n] = letter;
	n += 1;
	if (piece >= 26) {
		path[n] = ('a' + ((piece / 26) % 26)): u8;
		n += 1;
	};
	path[n] = 0;
	_ = rt::create(*(&path[..n]: *str));
	const wrote = rt::writefile(*(&path[..n]: *str), text);
	rt::print("wrote ");
	rt::printnum(wrote: u64);
	rt::print(" bytes to ");
	rt::println(*(&path[..n]: *str));
};
