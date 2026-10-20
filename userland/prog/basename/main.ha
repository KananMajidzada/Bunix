use lib;
use rt;

// basename path [suffix]
//
// The last element of a path, with any trailing suffix taken off when one is
// named. /usr/include/sys/stat.h gives stat.h, and with .h on the end it
// gives stat. It is the one piece of the shell that has no variables to hang
// on, so a script that wants it has to be given the answer some other way.

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let path = lib::arg_n(args, 0);
	if (len(path) == 0) {
		rt::println("usage: basename <path> [suffix]");
		return;
	};

	// A trailing slash is not part of the name, so "/usr/lib/" gives lib.
	let end = len(path);
	for (let i = 0u64; end > 1 && path[end - 1] == '/'; i += 1) {
		end -= 1;
	};
	path = path[..end];

	const name = lib::base_name(path);
	const suffix = lib::arg_n(args, 1);
	// The suffix only comes off when it is one, and a name that is nothing
	// but the suffix is left alone: basename of "x.txt" with suffix "x.txt" is
	// still "x.txt", not nothing.
	if (len(suffix) > 0 && len(name) > len(suffix)
			&& lib::ends_with(name, suffix)) {
		rt::println(*(&name[..len(name) - len(suffix)]: *str));
		return;
	};
	rt::println(*(&name: *str));
};