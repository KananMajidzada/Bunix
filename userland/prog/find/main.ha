use lib;
use rt;

def MAXDEPTH: size = 16;

let bufs: [MAXDEPTH][512]u8 = [[0...], [0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...],
	[0...], [0...]];

// Walks a tree and prints every path whose name matches the pattern. A * in
// the pattern stands for any run of characters.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: find <path> <pattern>");
		return;
	};
	const path = words[0];
	const pat = if (n > 1) words[1] else *(&"*": *[]u8);
	if (!rt::exists(*(&path: *str))) {
		rt::print("find: no such path: ");
		rt::println(*(&path: *str));
		return;
	};
	// The path itself may be the one that matches.
	if (lib::matches(base(path), pat)) {
		rt::println(*(&path: *str));
	};
	find(path, pat, 0);
};

// Walks a tree, printing the paths whose name matches. A file is only
// reported once, by the directory it is in, so the walk only goes on into
// the directories.
fn find(path: []u8, pat: []u8, depth: size) void = {
	if (depth >= MAXDEPTH) {
		return;
	};
	if (!rt::isdir(*(&path: *str))) {
		return;
	};
	let buf: [1024]u8 = [0...];
	const n = rt::readdir(*(&path: *str), buf[..]);
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				const name = buf[start..i];
				const full = join(bufs[depth], path, name);
				if (lib::matches(name, pat)) {
					rt::println(*(&full: *str));
				};
				if (rt::isdir(*(&full: *str))) {
					find(full, pat, depth + 1);
				};
			};
			start = i + 1;
		};
	};
};

// The last element of a path.
fn base(path: []u8) []u8 = {
	let end = len(path);
	for (end > 1 && path[end - 1] == ('/': u8)) {
		end -= 1;
	};
	let start = end;
	for (let i = 0z; i < end; i += 1) {
		if (path[i] == ('/': u8)) {
			start = i + 1;
		};
	};
	return path[start..end];
};

// A path made of a directory and a name in it, written into the given buffer.
fn join(buf: []u8, dir: []u8, name: []u8) []u8 = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n + 1 < len(buf); i += 1) {
		buf[n] = dir[i];
		n += 1;
	};
	if (n > 0 && buf[n - 1] != ('/': u8) && n + 1 < len(buf)) {
		buf[n] = ('/': u8);
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < len(buf); i += 1) {
		buf[n] = name[i];
		n += 1;
	};
	return buf[..n];
};

