use lib;
use rt;

// Moves a file. The new name may be another name in the same directory, or
// a path in another one. A move is a copy and then a removal, since the
// filesystem has no way to rename a thing in one step.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 2) {
		rt::println("usage: mv <from> <to>");
		return;
	};
	const from = words[0];
	const to = words[1];
	if (!rt::exists(*(&from: *str))) {
		rt::print("mv: no such file: ");
		rt::println(*(&from: *str));
		return;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("mv: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&from: *str), buf);
	if (flen == 0) {
		rt::print("mv: cannot read ");
		rt::println(*(&from: *str));
		return;
	};
	// The file is written where it is going, and the old one goes away.
	if (!rt::exists(*(&to: *str))) {
		_ = rt::create(*(&to: *str));
	};
	const wrote = rt::writefile(*(&to: *str), buf[..flen]);
	if (wrote != flen) {
		rt::print("mv: cannot write ");
		rt::println(*(&to: *str));
		return;
	};
	if (!rt::remove(*(&from: *str))) {
		rt::print("mv: cannot remove ");
		rt::println(*(&from: *str));
		return;
	};
	rt::print("moved ");
	rt::printnum(flen: u64);
	rt::print(" bytes to ");
	rt::println(*(&to: *str));
};
