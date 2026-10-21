use lib;
use rt;

const E_FLAG: str = "-e";
const F_FLAG: str = "-f";
const D_FLAG: str = "-d";
const S_FLAG: str = "-s";

// Asks about a path. "test -f /tmp/x" says whether it is a file, "test -d" a
// directory, "test -e" whether it is there at all, and "test -s" whether it
// has anything in it.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 2) {
		rt::println("usage: test -e|-f|-d|-s <path>");
		return;
	};
	const what = words[0];
	const path = words[1];
	let ok = false;
	if (lib::str_eq(what, *(&E_FLAG: *[]u8))) {
		ok = rt::exists(*(&path: *str));
	} else if (lib::str_eq(what, *(&F_FLAG: *[]u8))) {
		ok = rt::exists(*(&path: *str)) && !rt::isdir(*(&path: *str));
	} else if (lib::str_eq(what, *(&D_FLAG: *[]u8))) {
		ok = rt::isdir(*(&path: *str));
	} else if (lib::str_eq(what, *(&S_FLAG: *[]u8))) {
		ok = rt::exists(*(&path: *str)) && rt::filesize(*(&path: *str)) > 0;
	} else {
		rt::print("test: unknown test: ");
		rt::println(*(&what: *str));
		return;
	};
	rt::println(if (ok) "yes" else "no");
};
