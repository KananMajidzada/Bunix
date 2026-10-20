use lib;
use rt;

// du [path]
//
// How much room a tree takes, one line per thing under it and then the total.
// A directory is counted by adding up what is in it rather than by reading the
// directory itself, so the last line is the whole of what is there.

def MAXDEPTH: size = 24;
def LISTCAP: size = 1024;
def PATHCAP: size = 256;
def WIDTH: size = 9;

let lbuf: [MAXDEPTH][LISTCAP]u8 = [[0...]...];
let llen: [MAXDEPTH]size = [0...];
let pbuf: [MAXDEPTH][PATHCAP]u8 = [[0...]...];
let plen: [MAXDEPTH]size = [0...];
let total: u64 = 0;

fn load(d: size, path: []u8) void = {
	llen[d] = rt::readdir(*(&path: *str), lbuf[d][..]);
};

fn setpath(d: size, dir: []u8, name: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n < PATHCAP; i += 1) {
		pbuf[d][n] = dir[i];
		n += 1;
	};
	if (n > 0 && pbuf[d][n - 1] != ('/': u8)) {
		pbuf[d][n] = '/': u8;
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < PATHCAP; i += 1) {
		pbuf[d][n] = name[i];
		n += 1;
	};
	plen[d] = n;
	return n;
};

// Right-aligned in a fixed field, so the sizes line up down the listing.
fn line(path: []u8, bytes: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	let v = bytes;
	if (v == 0) {
		i -= 1;
		buf[i] = ('0': u8);
	} else {
		for (let k = 0u64; v > 0; k += 1) {
			i -= 1;
			buf[i] = ((v % 10): u8) + ('0': u8);
			v /= 10;
		};
	};
	for (let k = i; k < WIDTH; k += 1) {
		rt::putc(' ': u8);
	};
	rt::write(buf[i..]);
	rt::putc(' ': u8);
	rt::println(*(&path: *str));
};

// The bytes under one directory, and the line for it. Each level adds up its
// own children, which is what makes a plain depth-first walk enough.
fn walk(d: size, path: []u8) u64 = {
	if (d + 1 >= MAXDEPTH) {
		return 0;
	};
	load(d, path);
	const list = lbuf[d][..llen[d]];
	let at = 0z;
	let sum: u64 = 0;
	for (let k = 0z; at < len(list); k += 1) {
		let (name, next) = lib::name_at(list, at);
		at = next;
		if (len(name) == 0) {
			continue;
		};
		const n = setpath(d + 1, path, name);
		const child = pbuf[d + 1][..n];
		if (rt::isdir(*(&child: *str))) {
			const under = walk(d + 1, child);
			line(child, under);
			sum += under;
		} else {
			const bytes = rt::filesize(*(&child: *str));
			line(child, bytes);
			sum += bytes;
		};
	};
	return sum;
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	const pos = lib::skip_space(args, 0);
	let root = lib::root_dir();
	if (pos < len(args)) {
		root = lib::arg_n(args, 0);
	};
	if (!rt::exists(*(&root: *str))) {
		rt::print("du: no such path: ");
		rt::println(*(&root: *str));
		return;
	};

	if (!rt::isdir(*(&root: *str))) {
		line(root, rt::filesize(*(&root: *str)));
		return;
	};

	total = walk(0, root);
	line(root, total);
	rt::print("total ");
	rt::printnum(total);
	rt::println(" bytes");
};

