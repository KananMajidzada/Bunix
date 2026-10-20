use lib;
use rt;

// mv src dst
//
// Moves a file. The kernel has no rename of its own: a write always lands on a
// whole path and a delete takes one away, so a move is a read, a write and
// then an unlink. When the destination is a directory the file lands inside
// it under its own name, the way mv behaves everywhere else.

def PATHCAP: size = 256;

// The path under construction. It is short and does not have to outlive the
// call that built it.
let buf: [PATHCAP]u8 = [0...];

// Builds "dir/name" in a buffer of our own, since the two pieces come from
// different places and neither is long.
fn joined(dir: []u8, name: []u8) []u8 = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n < PATHCAP; i += 1) {
		buf[n] = dir[i];
		n += 1;
	};
	if (n > 0 && buf[n - 1] != ('/': u8)) {
		buf[n] = '/': u8;
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < PATHCAP; i += 1) {
		buf[n] = name[i];
		n += 1;
	};
	return buf[..n];
};

fn move_one(src: []u8, dst: []u8) void = {
	if (!rt::exists(*(&src: *str))) {
		rt::print("mv: no such file: ");
		rt::println(*(&src: *str));
		return;
	};
	const text = lib::slurp(src);
	if (len(text) == 0) {
		rt::print("mv: cannot read ");
		rt::println(*(&src: *str));
		return;
	};

	// A destination that is a directory means "put it in there", so the name
	// travels with the file rather than the file taking the directory's name.
	let target = dst;
	if (rt::isdir(*(&dst: *str))) {
		target = joined(dst, lib::base_name(src));
	};

	const wrote = rt::writefile(*(&target: *str), text);
	if (wrote != len(text)) {
		rt::print("mv: cannot write ");
		rt::println(*(&target: *str));
		lib::release(text);
		return;
	};
	lib::release(text);
	// The copy is the one that matters, so the original only goes once the new
	// file is whole. Removing first would lose the file on a failed write.
	if (!rt::remove(*(&src: *str))) {
		rt::print("mv: copied but could not remove ");
		rt::println(*(&src: *str));
		return;
	};
	rt::print("moved to ");
	rt::println(*(&target: *str));
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	if (lib::count_args(args) < 2) {
		rt::println("usage: mv <src> <dst>");
		return;
	};
	const src = lib::arg_n(args, 0);
	const dst = lib::arg_n(args, 1);
	if (len(dst) == 0) {
		rt::println("usage: mv <src> <dst>");
		return;
	};
	move_one(src, dst);
};