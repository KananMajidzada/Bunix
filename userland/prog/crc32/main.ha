use lib;
use rt;

// crc32 [file...]
//
// The CRC-32 of each file, its length, and its name. This is the one zip,
// gzip and PNG use, so a file checksummed here agrees with one checked on a
// host: it is what "cksum -a crc32b" prints on a current coreutils.
//
// It is deliberately not what a bare "cksum" prints. That default changed
// years ago to a variant of its own, and a program here that called itself
// cksum while disagreeing with every other cksum would be worse than useless.
// This one says what it computes and computes that.
//
// Reading a file whole is enough: the checksum does not care where the bytes
// come from, and the kernel hands a file over in one read anyway.

fn step(c: u32, b: u8) u32 = {
	// A table would be quicker, but it would be 1 KiB of bss in a program
	// that is otherwise a page, and a file here is a few kilobytes.
	let v = c ^ (b: u32);
	for (let i = 0u64; i < 8; i += 1) {
		if ((v & 1) != 0) {
			v = (v >> 1) ^ 0xEDB88320;
		} else {
			v = v >> 1;
		};
	};
	return v;
};

fn sum(text: []u8) u32 = {
	let c: u32 = 0xFFFFFFFF;
	for (let i = 0z; i < len(text); i += 1) {
		c = step(c, text[i]);
	};
	return c ^ 0xFFFFFFFF;
};

fn num(v: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	let x = v;
	if (x == 0) {
		i -= 1;
		buf[i] = ('0': u8);
	} else {
		for (let k = 0u64; x > 0; k += 1) {
			i -= 1;
			buf[i] = ((x % 10): u8) + ('0': u8);
			x /= 10;
		};
	};
	rt::write(buf[i..]);
};

fn one(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("crc32: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	num(sum(text): u64);
	rt::putc(' ': u8);
	num(len(text): u64);
	rt::putc(' ': u8);
	rt::println(*(&path: *str));
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let n = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		pos = next;
		if (k > 0) {
			rt::println("");
		};
		one(path);
		n += 1;
	};
	if (n == 0) {
		// With no file named, crc reads standard input, which here is the
		// keyboard until it is closed with Ctrl-D.
		let buf: [512]u8 = [0...];
		let len_ = 0z;
		for (true) {
			const c = rt::getchar();
			if (c == 4) {
				break;
			};
			if (c == ('\n': u8)) {
				continue;
			};
			if (len_ < len(buf)) {
				buf[len_] = c;
				len_ += 1;
			};
		};
		num(sum(buf[..len_]): u64);
		rt::putc(' ': u8);
		num(len_: u64);
		rt::println(" 0");
	};
};