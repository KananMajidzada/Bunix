use lib;
use rt;

// free
//
// How much memory is free, and how much there was to begin with. The kernel
// counts in frames rather than bytes and keeps no separate heap, so this is
// the whole of the memory picture a user process can get at.

fn memfile() []u8 = {
	return *(&"/proc/mem": *[]u8);
};

// Right-aligned in a column, so the sizes line up down the listing.
fn field(label: []u8, v: u64) void = {
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
	for (let k = i; k < 12; k += 1) {
		rt::putc(' ': u8);
	};
	rt::write(buf[i..]);
	rt::putc(' ': u8);
	rt::println(*(&label: *str));
};

// The two counts in "frames free N of M", which is the shape of /proc/mem.
// Reading them here rather than taking the word for it keeps free honest if
// the kernel's file ever says something else.
fn counts(text: []u8) (u64, u64) = {
	let first: u64 = 0;
	let second: u64 = 0;
	let seen: u64 = 0;
	let v: u64 = 0;
	let inside: bool = false;
	for (let i = 0z; i <= len(text); i += 1) {
		let c = ('\n': u8);
		if (i < len(text)) {
			c = text[i];
		};
		if (i < len(text) && lib::is_digit(c)) {
			v = v * 10 + (c - ('0': u8): u64);
			inside = true;
			continue;
		};
		if (inside) {
			seen += 1;
			if (seen == 1) {
				first = v;
			} else {
				second = v;
			};
			v = 0;
			inside = false;
		};
	};
	return (first, second);
};

export @symbol("main") fn main() void = {
	const mem = lib::slurp(memfile());
	if (len(mem) == 0) {
		rt::println("free: no memory file");
		return;
	};
	let (left, total) = counts(mem);
	lib::release(mem);
	if (total == 0) {
		rt::println("free: cannot read the memory file");
		return;
	};

	field(*(&"total": *[]u8), total);
	field(*(&"used": *[]u8), total - left);
	field(*(&"free": *[]u8), left);
	// A frame is 4 KiB, which is also what a program here is handed.
	field(*(&"free KiB": *[]u8), left * 4);
	rt::println("");
	rt::print("free: ");
	rt::printnum(left * 100 / total);
	rt::println("% of frames");
};