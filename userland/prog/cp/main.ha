use lib;
use posix;
use rt;

// Copy a file through the POSIX interface, a block at a time.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const rest = *(&a: *[]u8);
	const sp = lib::first_space(rest);
	if (sp == len(rest)) {
		rt::println("usage: cp <src> <dst>");
		return;
	};
	const src = rest[..sp];
	const dst = rest[sp + 1..];
	const in = posix::open(*(&src: *str), posix::O_RDONLY);
	if (in < 0) {
		rt::println("cp: cannot read source");
		return;
	};
	const out = posix::open(*(&dst: *str), posix::O_WRONLY | posix::O_CREAT);
	if (out < 0) {
		posix::close(in);
		rt::println("cp: cannot create target");
		return;
	};
	let buf: [512]u8 = [0...];
	for (true) {
		const n = posix::read(in, buf[..]);
		if (n == 0) {
			break;
		};
		_ = posix::write(out, buf[..n]);
	};
	posix::close(in);
	posix::close(out);
	rt::println("copied");
};
