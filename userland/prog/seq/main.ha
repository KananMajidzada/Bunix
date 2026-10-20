use lib;
use rt;

// seq [first [incr]] last
//
// The numbers from first to last, stepping by incr. With one argument it
// counts from one, which is the form that is nearly always wanted. A count of
// zero or less is a count of one, so a shell arithmetic slip cannot leave this
// running forever.

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	const n = lib::count_args(args);
	if (n == 0) {
		rt::println("usage: seq [first [incr]] last");
		return;
	};

	let first: i64 = 1;
	let incr: i64 = 1;
	let last: i64 = 0;
	if (n == 1) {
		last = lib::parse_int(lib::arg_n(args, 0), 0): i64;
	} else {
		first = lib::parse_int(lib::arg_n(args, 0), 1): i64;
		last = lib::parse_int(lib::arg_n(args, n - 1), 0): i64;
		if (n > 2) {
			incr = lib::parse_int(lib::arg_n(args, 1), 1): i64;
		};
	};
	if (incr <= 0) {
		incr = 1;
	};

	// The loop condition is the end of the range, so the step never runs one
	// past it and the count stays even when last sits between two numbers.
	let v = first;
	for (let i = 0u64; true; i += 1) {
		if (incr > 0 && v > last) {
			break;
		};
		if (incr < 0 && v < last) {
			break;
		};
		rt::printnum(v: u64);
		rt::println("");
		v += incr;
		// A range wide enough to fill the screen is a mistake rather than a
		// request; stop rather than run the console dry.
		if (i > 100000) {
			rt::println("seq: too many");
			break;
		};
	};
};