use lib;
use rt;

// Says what a path is: a directory or a file, and how big it is.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: stat <path>");
		return;
	};
	for (let i = 0z; i < n; i += 1) {
		const path = words[i];
		if (!rt::exists(*(&path: *str))) {
			rt::print("stat: no such file: ");
			rt::println(*(&path: *str));
			continue;
		};
		const isdir = rt::isdir(*(&path: *str));
		rt::print("  file: ");
		rt::println(*(&path: *str));
		rt::print("  type: ");
		rt::println(if (isdir) "directory" else "file");
		rt::print("  size: ");
		if (isdir) {
			rt::println("0");
		} else {
			rt::printnum(rt::filesize(*(&path: *str)));
			rt::println("");
		};
	};
};
