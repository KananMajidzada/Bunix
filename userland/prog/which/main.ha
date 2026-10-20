use lib;
use rt;

// which name...
//
// Whether each name is something the shell can run, and where it would find
// it. The programs that run from the kernel have an image of their own under
// /bin, so that directory is the whole of the answer: a name that is not in
// it is not a program, however much it looks like one.

def HITCAP: size = 128;

let hit: [HITCAP]u8 = [0...];
let hitlen: size = 0;

fn bindir() []u8 = {
	return *(&"/bin": *[]u8);
};

// Puts "/bin/<name>" together, so which answers with something that can be
// typed back at the shell rather than with a bare name.
fn remember(entry: []u8) void = {
	const prefix: str = "/bin/";
	const pb = *(&prefix: *[]u8);
	hitlen = 0;
	for (let i = 0z; i < len(pb) && hitlen < len(hit); i += 1) {
		hit[hitlen] = pb[i];
		hitlen += 1;
	};
	for (let i = 0z; i < len(entry) && hitlen < len(hit); i += 1) {
		hit[hitlen] = entry[i];
		hitlen += 1;
	};
};

// The listing goes through lib's own buffer rather than one on the stack. A
// directory listing here is a couple of hundred bytes and the kernel already
// keeps one spare; taking two kilobytes of stack for it is what a program
// should not be doing when it may be one of several running.
fn have(name: []u8) bool = {
	const list = lib::listdir(bindir());
	let at = 0z;
	for (let k = 0z; at < len(list); k += 1) {
		let (entry, next) = lib::name_at(list, at);
		at = next;
		if (lib::str_eq(entry, name)) {
			remember(entry);
			return true;
		};
	};
	return false;
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let n: size = 0;
	for (let k = 0z; pos < len(args); k += 1) {
		let (name, next) = lib::next_arg(args, pos);
		pos = next;
		n += 1;
		// A name with a slash in it is already a path, and the loader is what
		// decides what runs; which only answers for plain names.
		if (lib::index_of(name, '/': u8) < len(name)) {
			rt::println(*(&name: *str));
			continue;
		};
		if (have(name)) {
			rt::println(*(&hit[..hitlen]: *str));
		} else {
			rt::print("which: ");
			rt::println(*(&name: *str));
			rt::println("not found");
		};
	};
	if (n == 0) {
		rt::println("usage: which <name>...");
	};
};