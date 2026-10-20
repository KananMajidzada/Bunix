use lib;
use rt;

// sleep seconds
//
// Waits, so that a sequence of commands typed at the shell can be spaced out.
// The clock is the same one /proc/uptime counts, so the wait is in whole
// seconds and nothing finer: there is no sub-second time here to be exact
// with. The process yields between reads rather than spinning, so the rest of
// the system carries on while it waits.

fn up() []u8 = {
	return *(&"/proc/uptime": *[]u8);
};

// The kernel's own count, which is the only clock there is.
fn now() u64 = {
	const text = lib::slurp(up());
	if (len(text) == 0) {
		return 0;
	};
	let v: u64 = 0;
	for (let i = 0z; i < len(text) && lib::is_digit(text[i]); i += 1) {
		v = v * 10 + (text[i] - ('0': u8): u64);
	};
	lib::release(text);
	return v;
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	if (lib::count_args(args) == 0) {
		rt::println("usage: sleep <seconds>");
		return;
	};
	const secs = lib::parse_int(lib::arg_n(args, 0), 0);
	if (secs > 3600) {
		rt::println("sleep: a whole hour is long enough");
		return;
	};

	const start = now();
	if (start == 0) {
		rt::println("sleep: no clock");
		return;
	};
	const stop = start + secs;
	// The loop condition is the clock, so it ends by itself once the time is
	// up rather than trusting the count of turns around it.
	for (let i = 0u64; now() < stop; i += 1) {
		rt::cop();
	};
};