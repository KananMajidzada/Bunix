use posix;
use rt;

// Number the bytes, the lines, and the words of a file.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const path = *(&a: *[]u8);
	if (len(path) == 0) {
		rt::println("usage: wc <path>");
		return;
	};
	const fd = posix::open(a, posix::O_RDONLY);
	if (fd < 0) {
		rt::println("wc: cannot open");
		return;
	};
	let buf: [512]u8 = [0...];
	let bytes = 0u64, lines = 0u64, words = 0u64;
	let inword = false;
	for (true) {
		const n = posix::read(fd, buf[..]);
		if (n == 0) {
			break;
		};
		for (let i = 0z; i < n; i += 1) {
			const c = buf[i];
			bytes += 1;
			if (c == ('\n': u8)) {
				lines += 1;
			};
			if (c == (' ': u8) || c == ('\n': u8) || c == ('\t': u8)) {
				inword = false;
			} else if (!inword) {
				inword = true;
				words += 1;
			};
		};
	};
	posix::close(fd);
	rt::printnum(lines);
	rt::print(" ");
	rt::printnum(words);
	rt::print(" ");
	rt::printnum(bytes);
	rt::print(" ");
	rt::println(a);
};
