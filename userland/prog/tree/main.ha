use lib;
use rt;

def MAXDEPTH: size = 16;

let bufs: [MAXDEPTH][512]u8 = [[0...], [0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...],
	[0...], [0...]];

// Prints a directory as a tree, with the names indented under the one above.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: tree <path>");
		return;
	};
	const path = words[0];
	if (!rt::exists(*(&path: *str))) {
		rt::print("tree: no such path: ");
		rt::println(*(&path: *str));
		return;
	};
	rt::println(*(&path: *str));
	tree(path, 1, 0);
};

fn tree(path: []u8, depth: size, level: size) void = {
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
				for (let k = 0z; k < level; k += 1) {
					rt::print("  ");
				};
				rt::println(*(&name: *str));
				tree(full, depth + 1, level + 1);
			};
			start = i + 1;
		};
	};
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
