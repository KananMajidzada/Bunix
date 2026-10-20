use lib;
use rt;

// find [path] -name pattern
//
// Every name under a path that matches. The shell has no pipes and no glob, so
// this is how a question like "where is stat.h" gets answered: it walks the
// tree rather than the reader going through it a level at a time.
//
// The pattern may hold * and ?, the two wildcards a name search actually
// needs.
//
// Each level of the walk keeps its own listing and path in a slot indexed by
// depth. One shared buffer would be smaller, but the recursion below would
// overwrite it out from under the level that is walking.

def MAXDEPTH: size = 24;
def LISTCAP: size = 1024;
def PATHCAP: size = 256;

let lbuf: [MAXDEPTH][LISTCAP]u8 = [[0...]...];
let llen: [MAXDEPTH]size = [0...];
let pbuf: [MAXDEPTH][PATHCAP]u8 = [[0...]...];
let plen: [MAXDEPTH]size = [0...];
let pat: [PATHCAP]u8 = [0...];
let patlen: size = 0;
let found: u64 = 0;

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

// * stands for any run of bytes and ? for exactly one. Walking the two
// together means a leading wildcard does not have to be tried at every place
// it could start.
fn wild(name: []u8, p: []u8, ni: size, pi: size) bool = {
	let n = ni;
	let q = pi;
	for (let step = 0u64; true; step += 1) {
		if (q >= len(p)) {
			return n >= len(name);
		};
		if (p[q] == ('*': u8)) {
			if (wild(name, p, n, q + 1)) {
				return true;
			};
			if (n >= len(name)) {
				return false;
			};
			n += 1;
			continue;
		};
		if (n >= len(name)) {
			return false;
		};
		if (p[q] != ('?': u8) && p[q] != name[n]) {
			return false;
		};
		n += 1;
		q += 1;
	};
};

fn matches(name: []u8) bool = {
	if (patlen == 0) {
		return true;
	};
	return wild(name, pat[..patlen], 0, 0);
};

fn report(path: []u8) void = {
	rt::println(*(&path: *str));
	found += 1;
};

fn walk(d: size, checkstart: bool) void = {
	if (d + 1 >= MAXDEPTH) {
		return;
	};
	if (checkstart && matches(pbuf[d][..plen[d]])) {
		report(pbuf[d][..plen[d]]);
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
		if (!rt::isdir(*(&child: *str))) {
			if (matches(name)) {
				report(child);
			};
		} else {
			load(d + 1, child);
			walk(d + 1, false);
		};
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let root = lib::root_dir();
	if (pos < len(args) && args[pos] != ('-': u8)) {
		let (path, next) = lib::next_arg(args, pos);
		root = path;
		pos = next;
	};

	for (let f = 0z; pos < len(args); f += 1) {
		let (tok, next) = lib::next_arg(args, pos);
		if (lib::eq_str(tok, "-name") || lib::eq_str(tok, "-iname")) {
			let (val, after) = lib::next_arg(args, next);
			if (len(val) == 0) {
				rt::println("find: -name wants a pattern");
				return;
			};
			patlen = if (len(val) > PATHCAP) PATHCAP else len(val);
			for (let i = 0z; i < patlen; i += 1) {
				pat[i] = val[i];
			};
			pos = after;
			continue;
		};
		rt::print("find: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	if (!rt::exists(*(&root: *str))) {
		rt::print("find: no such path: ");
		rt::println(*(&root: *str));
		return;
	};

	// The walk needs the starting path in its own slot, spelled the way the
	// reader gave it: a bare root stays a bare root.
	for (let i = 0z; i < len(root) && i < PATHCAP; i += 1) {
		pbuf[0][i] = root[i];
	};
	plen[0] = if (len(root) < PATHCAP) len(root) else PATHCAP;

	if (rt::isdir(*(&pbuf[0][..plen[0]]: *str))) {
		load(0, pbuf[0][..plen[0]]);
		walk(0, true);
	} else if (matches(pbuf[0][..plen[0]])) {
		report(pbuf[0][..plen[0]]);
	};
	if (found == 0) {
		rt::println("nothing found");
	};
};