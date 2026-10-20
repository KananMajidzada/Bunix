use lib;
use rt;

// tree [path]
//
// A directory and everything under it, drawn with the shape of the tree in the
// names. It is the answer to "what is in here" that a flat listing cannot
// give, and the first thing worth running against /usr once the system is up.
//
// Each level of the walk keeps its own listing and path in a slot indexed by
// depth. Sharing one buffer would be smaller, but the recursion below would
// overwrite it out from under the level that is walking.

def MAXDEPTH: size = 24;
def LISTCAP: size = 1024;
def PATHCAP: size = 256;
def INDENT: size = 2;

let lbuf: [MAXDEPTH][LISTCAP]u8 = [[0...]...];
let llen: [MAXDEPTH]size = [0...];
let pbuf: [MAXDEPTH][PATHCAP]u8 = [[0...]...];
let plen: [MAXDEPTH]size = [0...];

// Puts the path the walk starts at into its first slot. Each level below
// builds its children from the one above, so without this every name comes out
// on its own and nothing below the top can be found or measured.
fn seed(root: []u8) void = {
	for (let i = 0z; i < len(root) && i < PATHCAP; i += 1) {
		pbuf[0][i] = root[i];
	};
	plen[0] = if (len(root) < PATHCAP) len(root) else PATHCAP;
};

// Copies a directory's names into this level's slot.
fn load(d: size, path: []u8) void = {
	llen[d] = rt::readdir(*(&path: *str), lbuf[d][..]);
};

// Writes dir + "/" + name into the next level's slot and says how long it is.
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

fn pad(d: size) void = {
	for (let i = 0z; i < d * INDENT; i += 1) {
		rt::putc(' ': u8);
	};
};

fn walk(d: size) void = {
	// One level below this one is the first thing walk() touches, so this is
	// the depth at which the tree is too deep to keep drawing.
	if (d + 1 >= MAXDEPTH) {
		rt::print("... ");
		rt::write(pbuf[d][..plen[d]]);
		rt::println(" (deeper than this goes)");
		return;
	};
	const list = lbuf[d][..llen[d]];
	let at = 0z;
	for (let k = 0z; at < len(list); k += 1) {
		let (name, next) = lib::name_at(list, at);
		at = next;
		if (len(name) == 0) {
			continue;
		};
		const n = setpath(d + 1, pbuf[d][..plen[d]], name);
		const child = pbuf[d + 1][..n];
		const isdir = rt::isdir(*(&child: *str));

		pad(d + 1);
		rt::write(name);
		if (isdir) {
			rt::println("/");
			load(d + 1, child);
			walk(d + 1);
		} else {
			rt::print("  ");
			rt::printnum(rt::filesize(*(&child: *str)));
			rt::println("");
		};
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let root = lib::root_dir();
	let at = lib::skip_space(args, 0);
	if (at < len(args)) {
		let (path, next) = lib::next_arg(args, at);
		root = path;
		at = next;
	};
	if (at < len(args)) {
		rt::println("usage: tree [path]");
		return;
	};

	if (!rt::exists(*(&root: *str))) {
		rt::print("tree: no such path: ");
		rt::println(*(&root: *str));
		return;
	};
	if (!rt::isdir(*(&root: *str))) {
		rt::write(root);
		rt::println(" is not a directory");
		return;
	};

	rt::write(root);
	rt::println("/");
	seed(root);
	load(0, pbuf[0][..plen[0]]);
	walk(0);
};

