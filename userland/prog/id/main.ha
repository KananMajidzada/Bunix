use lib;
use rt;

// Which process this is. Every process has a number, and that is all there
// is to say about who it is.
export @symbol("main") fn main() void = {
	let buf: [64]u8 = [0...];
	const n = rt::readfile("/proc/self", buf[..]);
	if (n == 0) {
		rt::println("id: cannot read /proc/self");
		return;
	};
	rt::write(buf[..n]);
};
