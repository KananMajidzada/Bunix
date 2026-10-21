use lib;
use rt;

def MAXDEPTH: size = 16;

// One buffer for each level of the walk, so a path being looked at is not
// overwritten by the path being built below it.
let bufs: [MAXDEPTH][512]u8 = [[0...], [0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...],
	[0...], [0...]];

// The size of a path and everything under it.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: du <path>");
		return;
	};
	for (let i = 0z; i < n; i += 1) {
		const path = words[i];
		if (!rt::exists(*(&path: *str))) {
			rt::print("du: no such file: ");
			rt::println(*(&path: *str));
			continue;
		};
		rt::printnum(du(path, 0));
		rt::print(" ");
		rt::println(*(&path: *str));
	};
};

// The size of a path, and of everything in it if it is a directory.
fn du(path: []u8, depth: size) u64 = {
	if (depth >= MAXDEPTH) {
		return 0;
	};
	if (!rt::isdir(*(&path: *str))) {
		return rt::filesize(*(&path: *str));
	};
	let buf: [1024]u8 = [0...];
	const n = rt::readdir(*(&path: *str), buf[..]);
	let total: u64 = 0;
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				const name = buf[start..i];
				const full = join(bufs[depth], path, name);
				total += du(full, depth + 1);
			};
			start = i + 1;
		};
	};
	return total;
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
