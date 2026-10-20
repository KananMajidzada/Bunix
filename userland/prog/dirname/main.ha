use lib;
use rt;

// dirname path
//
// The directory part of a path: /usr/include/sys/stat.h gives /usr/include/sys.
// The other half of basename, which gives stat.h.

fn noslash() str = {
	return ".";
};

fn rootonly() str = {
	return "/";
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let path = lib::arg_n(args, 0);
	if (len(path) == 0) {
		rt::println("usage: dirname <path>");
		return;
	};

	// A trailing slash is not part of a directory's name, so "/usr/lib/" gives
	// /usr/lib rather than /usr/lib itself with nothing after it.
	let end = len(path);
	for (let i = 0u64; end > 1 && path[end - 1] == '/'; i += 1) {
		end -= 1;
	};
	path = path[..end];

	// The last slash, and if there is none then the whole thing names
	// something in the directory this process is already standing in.
	let at = 0z;
	for (let i = 0z; i < len(path); i += 1) {
		if (path[i] == ('/': u8)) {
			at = i + 1;
		};
	};
	if (at == 0) {
		rt::println(noslash());
		return;
	};
	// "/usr" has a slash at the front and nothing after it, so what is left
	// is the root rather than nothing at all.
	if (at == 1) {
		rt::println(rootonly());
		return;
	};
	rt::println(*(&path[..at - 1]: *str));
};