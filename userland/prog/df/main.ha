use lib;
use rt;

// How much room is left, on the disk and in memory.
export @symbol("main") fn main() void = {
	rt::print("disk:   ");
	show("/proc/disk");
	rt::print("memory: ");
	show("/proc/mem");
};

fn show(path: str) void = {
	let buf: [256]u8 = [0...];
	const n = rt::readfile(path, buf[..]);
	rt::write(buf[..n]);
};
