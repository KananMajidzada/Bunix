use lib;
use rt;

// nproc
//
// How many threads the kernel is running. There are no separate processes to
// count here: every program this kernel starts is a thread in one address
// space with the window it was given, so the live count is the whole answer.

fn threadsfile() []u8 = {
	return *(&"/proc/threads": *[]u8);
};

// The first run of digits in the file. It is not at the front: the kernel
// writes "threads N", so the number has to be looked for.
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

export @symbol("main") fn main() void = {
	const text = lib::slurp(threadsfile());
	if (len(text) == 0) {
		rt::println("nproc: no threads file");
		return;
	};
	const n = digits(text);
	if (len(n) == 0) {
		rt::println("nproc: cannot read the threads file");
		lib::release(text);
		return;
	};
	rt::println(*(&n: *str));
	lib::release(text);
};