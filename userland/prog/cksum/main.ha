use lib;
use rt;

// A checksum of a file, and its size. The checksum is a sum of the bytes
// with a bit of rotation mixed in, so that a change in one byte shows up.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: cksum <path>");
		return;
	};
	const path = words[0];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("cksum: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("cksum: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let sum: u64 = 0;
	for (let i = 0z; i < flen; i += 1) {
		// The sum is rotated a little as it goes, so that the order of
		// the bytes matters.
		sum = ((sum << 1) | (sum >> 15)) & 0xFFFF;
		sum = (sum + (buf[i]: u64)) & 0xFFFF;
	};
	rt::printnum(sum);
	rt::print(" ");
	rt::printnum(flen: u64);
	rt::print(" ");
	rt::println(*(&path: *str));
};
