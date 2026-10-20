use lib;
use rt;

// cmp a b
//
// Whether two files hold the same bytes, and if they do not, where they first
// part company. Reading them whole is the simple way to do it here: the
// kernel hands a file over in one read, so a block-at-a-time comparison would
// be no cheaper and would not see anything the other way misses.

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

fn hex2(v: u8) void = {
	rt::putc(hexdig(v >> 4));
	rt::putc(hexdig(v & 0x0F));
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	if (lib::count_args(args) < 2) {
		rt::println("usage: cmp <file> <file>");
		return;
	};
	const a = lib::slurp(lib::arg_n(args, 0));
	const b = lib::slurp(lib::arg_n(args, 1));
	if (len(a) == 0 || len(b) == 0) {
		rt::println("cmp: cannot read both files");
		if (len(a) > 0) {
			lib::release(a);
		};
		if (len(b) > 0) {
			lib::release(b);
		};
		return;
	};

	const n = if (len(a) < len(b)) len(a) else len(b);
	for (let i = 0z; i < n; i += 1) {
		if (a[i] == b[i]) {
			continue;
		};
		rt::print("byte ");
		rt::printnum(i: u64);
		rt::print(": ");
		hex2(a[i]);
		rt::print(" vs ");
		hex2(b[i]);
		rt::println("");
		lib::release(a);
		lib::release(b);
		return;
	};

	if (len(a) == len(b)) {
		rt::println("identical");
	} else {
		rt::print("differ: ");
		rt::printnum(len(a): u64);
		rt::print(" and ");
		rt::printnum(len(b): u64);
		rt::println(" bytes");
	};
	lib::release(a);
	lib::release(b);
};