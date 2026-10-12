use lib;
use posix;
use rt;

// Print every line of a file that holds a pattern.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const rest = *(&a: *[]u8);
	const sp = lib::first_space(rest);
	if (sp == len(rest)) {
		rt::println("usage: grep <pattern> <path>");
		return;
	};
	const pat = rest[..sp];
	const path = rest[sp + 1..];
	const fd = posix::open(*(&path: *str), posix::O_RDONLY);
	if (fd < 0) {
		rt::println("grep: cannot open");
		return;
	};
	let buf: [512]u8 = [0...];
	let line: [512]u8 = [0...];
	let nl = 0z;
	for (true) {
		const n = posix::read(fd, buf[..]);
		if (n == 0) {
			if (nl > 0 && lib::contains(line[..nl], pat)) {
				rt::write(line[..nl]);
				rt::println("");
			};
			break;
		};
		for (let i = 0z; i < n; i += 1) {
			line[nl] = buf[i];
			const eol = buf[i] == ('\n': u8);
			if (!eol) {
				nl += 1;
			};
			if (eol || nl == len(line)) {
				if (lib::contains(line[..nl], pat)) {
					rt::write(line[..nl]);
					rt::println("");
				};
				nl = 0;
			};
		};
	};
	posix::close(fd);
};
