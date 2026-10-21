use lib;
use rt;

// Lists the entries of a directory. With -l each entry is shown with what it
// is and how big it is, and with -R the directories are looked into as well.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const line = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(line, &words);
	let long = false;
	let deep = false;
	let paths: [lib::MAXWORDS][]u8 = [[]...];
	let npath = 0z;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (len(w) > 1 && w[0] == ('-': u8)) {
			// The flags come before the names of the files, and more
			// than one of them can be in the same word.
			let ok = true;
			for (let j = 1z; j < len(w); j += 1) {
				if (w[j] == ('l': u8)) {
					long = true;
				} else if (w[j] == ('R': u8)) {
					deep = true;
				} else {
					ok = false;
				};
			};
			if (ok) {
				continue;
			};
		};
		if (npath < lib::MAXWORDS) {
			paths[npath] = w;
			npath += 1;
		};
	};
	if (npath == 0) {
		// With no path named, the directory the program is in is the one
		// that is listed.
		const here = rt::getcwd();
		paths[0] = *(&here: *[]u8);
		npath = 1;
	};
	for (let i = 0z; i < npath; i += 1) {
		list(paths[i], long, npath > 1, deep);
	};
};

let fullbuf: [512]u8 = [0...];

// A path made of a directory and a name in it.
fn join(dir: []u8, name: []u8) []u8 = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n + 1 < len(fullbuf); i += 1) {
		fullbuf[n] = dir[i];
		n += 1;
	};
	if (n > 0 && fullbuf[n - 1] != ('/': u8) && n + 1 < len(fullbuf)) {
		fullbuf[n] = ('/': u8);
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < len(fullbuf); i += 1) {
		fullbuf[n] = name[i];
		n += 1;
	};
	return fullbuf[..n];
};

// One entry with its kind and its size.
fn show_long(dir: []u8, name: []u8) void = {
	const full = join(dir, name);
	const isdir = rt::isdir(*(&full: *str));
	rt::write(name);
	for (let i = len(name); i < 24; i += 1) {
		rt::putc(' ');
	};
	if (isdir) {
		rt::print("dir ");
	} else {
		rt::print("    ");
	};
	rt::printnum(rt::filesize(*(&full: *str)));
	rt::println("");
};

// A file that is not in a directory, with its size.
fn show_file(path: []u8) void = {
	rt::write(path);
	for (let i = len(path); i < 24; i += 1) {
		rt::putc(' ');
	};
	rt::print("    ");
	rt::printnum(rt::filesize(*(&path: *str)));
	rt::println("");
};

// The names of a directory, one per line. A path that is not a directory is
// listed as itself, the way a listing of one file works. When there is more
// than one path, a directory says which one it is.
fn list(path: []u8, long: bool, many: bool, deep: bool) void = {
	if (!rt::isdir(*(&path: *str))) {
		if (!rt::exists(*(&path: *str))) {
			rt::print("ls: no such file: ");
			rt::println(*(&path: *str));
			return;
		};
		if (long) {
			show_file(path);
		} else {
			rt::write(path);
			rt::println("");
		};
		return;
	};
	if (many) {
		rt::write(path);
		rt::println(":");
	};
	let buf: [1024]u8 = [0...];
	const n = rt::readdir(*(&path: *str), buf[..]);
	if (n == 0) {
		rt::print("ls: nothing in ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				const name = buf[start..i];
				if (long) {
					show_long(path, name);
				} else {
					rt::write(name);
					rt::println("");
				};
				if (deep) {
					descend(path, name, long);
				};
			};
			start = i + 1;
		};
	};
};

// Looks into a directory that is in a directory, when the listing is to be
// of everything below it. The path is put in a buffer of its own, because
// the buffer the name is joined in is used again by the listing below.
fn descend(dir: []u8, name: []u8, long: bool) void = {
	const full = join(dir, name);
	if (!rt::isdir(*(&full: *str))) {
		return;
	};
	let sub: [512]u8 = [0...];
	let n = 0z;
	for (let i = 0z; i < len(full) && n < len(sub); i += 1) {
		sub[n] = full[i];
		n += 1;
	};
	rt::write(sub[..n]);
	rt::println(":");
	list(sub[..n], long, false, true);
};
