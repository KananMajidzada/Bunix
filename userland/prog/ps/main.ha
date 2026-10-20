use lib;
use rt;

// ps
//
// What is running. The kernel keeps one table of threads rather than a table
// of processes, and exposes only what it can stand behind: how many are live,
// and which slot this program is in. Naming each one and saying what it is
// doing would take a process table in the kernel, which is not there to ask.
//
// Saying so is better than printing a list of one line that looks like a
// system with nothing on it.

fn up() []u8 = {
	return *(&"/proc/threads": *[]u8);
};

fn self() []u8 = {
	return *(&"/proc/self": *[]u8);
};

// The first run of digits in the text. None of the /proc files put their
// number at the front, so it has to be looked for.
fn digits(b: []u8) []u8 = {
	let start = 0z;
	for (let i = 0z; i < len(b); i += 1) {
		if (lib::is_digit(b[i])) {
			start = i;
			break;
		};
	};
	if (start >= len(b)) {
		return b[len(b)..];
	};
	let end = start;
	for (let i = start; i < len(b) && lib::is_digit(b[i]); i += 1) {
		end = i + 1;
	};
	return b[start..end];
};

fn row(name: str, value: []u8) void = {
	rt::print(name);
	for (let i = 0z; i < 15; i += 1) {
		rt::putc(' ': u8);
	};
	rt::println(*(&value: *str));
};

export @symbol("main") fn main() void = {
	const threads = lib::slurp(up());
	const me = lib::slurp(self());
	if (len(threads) == 0 || len(me) == 0) {
		rt::println("ps: no process file");
		return;
	};
	row("this process", digits(me));
	row("live threads", digits(threads));
	rt::println("");
	rt::println("ps: the kernel keeps one table of threads, so there is no");
	rt::println("    per-process table to list. See /proc for what it has.");
	lib::release(threads);
	lib::release(me);
};