use lib;
use rt;

// stat [file...]
//
// What a path is: a directory or a file, and for a file how many bytes it
// holds. The kernel answers this without moving any bytes, so it is cheap
// enough to ask about a file far larger than would fit to read.

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		const p = *(&path: *str);
		if (!rt::exists(p)) {
			rt::print("stat: no such file: ");
			rt::println(*(&path: *str));
		} else if (rt::isdir(p)) {
			rt::write(path);
			rt::println(": directory");
		} else {
			rt::write(path);
			rt::print(": ");
			rt::printnum(rt::filesize(p));
			rt::println(" bytes");
		};
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: stat [file...]");
	};
};