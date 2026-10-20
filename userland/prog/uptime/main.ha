use lib;
use rt;

// uptime
//
// How long the kernel has been running, in seconds and in words. The clock
// starts at boot and nothing steps it backwards, so this is exact.

fn up() []u8 = {
	return *(&"/proc/uptime": *[]u8);
};

const MIN: u64 = 60;
const HOUR: u64 = 3600;
const DAY: u64 = 86400;

fn num(v: u64) void = {
	rt::printnum(v);
};

fn plural(v: u64, word: []u8) void = {
	num(v);
	rt::putc(' ': u8);
	rt::write(word);
	if (v != 1) {
		rt::putc('s': u8);
	};
	rt::putc(' ': u8);
};

export @symbol("main") fn main() void = {
	const text = lib::slurp(up());
	if (len(text) == 0) {
		rt::println("uptime: no uptime file");
		return;
	};
	let secs: u64 = 0;
	let seen: bool = false;
	for (let i = 0z; i < len(text) && lib::is_digit(text[i]); i += 1) {
		secs = secs * 10 + (text[i] - ('0': u8): u64);
		seen = true;
	};
	lib::release(text);
	if (!seen) {
		rt::println("uptime: cannot read the uptime file");
		return;
	};

	rt::print("up ");
	plural(secs / DAY, *(&"day": *[]u8));
	let rem = secs % DAY;
	plural(rem / HOUR, *(&"hour": *[]u8));
	rem = rem % HOUR;
	plural(rem / MIN, *(&"min": *[]u8));
	num(rem % MIN);
	rt::print(" sec");
	rt::println("");
};