use lib;
use rt;

// The last element of a path. The name of a file, with the directories
// around it taken off.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: basename <path>");
		return;
	};
	const path = words[0];
	// The last part is what comes after the final slash. A slash at the
	// end is not part of the name.
	let end = len(path);
	for (end > 1 && path[end - 1] == ('/': u8)) {
		end -= 1;
	};
	let start = end;
	for (let i = 0z; i < end; i += 1) {
		if (path[i] == ('/': u8)) {
			start = i + 1;
		};
	};
	rt::println(*(&path[start..end]: *str));
};
