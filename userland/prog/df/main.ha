use lib;
use rt;

// df
//
// How much room the disk has and how much of it is taken. The kernel keeps the
// figures in /proc/disk and generates them as they are read, so this is a
// lookup rather than a second opinion: a filesystem and its disk tool cannot
// disagree when there is only one of them.

def BLOCK: u64 = 512;

let sectors: u64 = 0;
let spare: u64 = 0;

fn pad(v: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	let x = v;
	for (let k = 0u64; k < 20 && x > 0; k += 1) {
		i -= 1;
		buf[i] = ((x % 10): u8) + ('0': u8);
		x /= 10;
	};
	for (let k = i; k < 10; k += 1) {
		rt::putc(' ': u8);
	};
	rt::write(buf[i..]);
	rt::putc(' ': u8);
};

fn column(name: str, v: u64) void = {
	rt::print(name);
	for (let i = 0u64; i < 18; i += 1) {
		rt::putc(' ': u8);
	};
	pad(v);
	rt::println("");
};

fn read_disk() bool = {
	const text = lib::slurp(diskfile());
	if (len(text) == 0) {
		return false;
	};
	let seen: u64 = 0;
	sectors = 0;
	spare = 0;
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
				sectors = v;
			} else {
				spare = v;
			};
			v = 0;
			inside = false;
		};
	};
	lib::release(text);
	return seen >= 2;
};

fn diskfile() []u8 = {
	return *(&"/proc/disk": *[]u8);
};

export @symbol("main") fn main() void = {
	if (!read_disk()) {
		rt::println("df: no disk information");
		return;
	};
	if (sectors == 0) {
		rt::println("df: no drive attached");
		return;
	};
	// The whole thing is counted in sectors and nothing else in the disk code
	// works in anything else, so the sectors are the unit the numbers are in
	// and the bytes are a courtesy.
	const total = sectors * BLOCK;
	const left = spare * BLOCK;
	let used: u64 = 0;
	if (total > left) {
		used = total - left;
	};

	rt::print("Filesystem    ");
	pad(total);
	pad(used);
	pad(left);
	rt::print("Use%");
	rt::println("");
	column("/dev/disk", total);
	column("", used);
	column("", left);
	rt::print("use ");
	if (total > 0) {
		rt::printnum(used * 100 / total);
	} else {
		rt::print("0");
	};
	rt::println("%");
};