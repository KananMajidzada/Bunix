use lib;
use rt;

// The directory a path is in: everything but the last element.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: dirname <path>");
		return;
	};
	const path = words[0];
	let end = len(path);
	for (end > 1 && path[end - 1] == ('/': u8)) {
		end -= 1;
	};
	let start = 0z;
	for (let i = 0z; i < end; i += 1) {
		if (path[i] == ('/': u8)) {
			start = i + 1;
		};
	};
	if (start == 0) {
		// A name with no directory in it is in the current one.
		rt::println(".");
		return;
	};
	// The slash before the name goes too.
	let e = start - 1;
	for (e > 0 && path[e - 1] == ('/': u8)) {
		e -= 1;
	};
	rt::println(*(&path[..e]: *str));
};
