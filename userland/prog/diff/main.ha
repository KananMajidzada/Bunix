use lib;
use rt;

// diff a b
//
// Where two files part company, a line at a time. The lines the two have in
// common are printed unmarked, the ones only the first has are marked with a
// dash, and the ones only the second has are marked with a star.
//
// The common part is found by matching from the front and from the back and
// treating the rest as the difference. That is not the longest common
// subsequence, and it does not need to be: it names the one change that is
// there, and a file with two changes a long way apart still gets both.
//
// A side-by-side view would be nicer to read, but it wants a terminal wider
// than eighty columns and this console is eighty.

def MAXLINES: size = 2048;

let al: [MAXLINES][]u8 = [[]...];
let bl: [MAXLINES][]u8 = [[]...];
let na: size = 0;
let nb: size = 0;
let dropped: size = 0;

fn take(l: []u8) bool = {
	if (na >= MAXLINES) {
		dropped += 1;
		return true;
	};
	al[na] = l;
	na += 1;
	return true;
};

fn put(l: []u8) bool = {
	if (nb >= MAXLINES) {
		dropped += 1;
		return true;
	};
	bl[nb] = l;
	nb += 1;
	return true;
};

fn line(mark: u8, from: []u8) void = {
	rt::putc(mark);
	rt::println(*(&from: *str));
};

fn same(i: size) bool = {
	return lib::str_eq(al[i], bl[i]);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	if (lib::count_args(args) < 2) {
		rt::println("usage: diff <file> <file>");
		return;
	};
	const ta = lib::slurp(lib::arg_n(args, 0));
	const tb = lib::slurp(lib::arg_n(args, 1));
	if (len(ta) == 0 || len(tb) == 0) {
		rt::println("diff: cannot read both files");
		if (len(ta) > 0) {
			lib::release(ta);
		};
		if (len(tb) > 0) {
			lib::release(tb);
		};
		return;
	};
	na = 0;
	nb = 0;
	dropped = 0;
	lib::each_line(ta, &take);
	lib::each_line(tb, &put);

	// How far the two agree from the front, and from the back. The tail is
	// taken against what is left after the head, so a file compared with
	// itself does not count every line as both.
	let head: size = 0;
	for (let i = 0z; i < na && i < nb; i += 1) {
		if (!same(i)) {
			break;
		};
		head = i + 1;
	};
	let tail: size = 0;
	for (let i = 0z; i + head < na && i + head < nb; i += 1) {
		if (!same(na - 1 - i)) {
			break;
		};
		tail = i + 1;
	};

	const enda = na - tail;
	const endb = nb - tail;
	if (head == enda && head == endb) {
		rt::println("files are the same");
	} else {
		for (let i = 0z; i < head; i += 1) {
			line(' ': u8, al[i]);
		};
		for (let i = head; i < enda; i += 1) {
			line('-': u8, al[i]);
		};
		for (let i = head; i < endb; i += 1) {
			line('*': u8, bl[i]);
		};
		for (let i = enda; i < na; i += 1) {
			line(' ': u8, al[i]);
		};
	};
	if (dropped > 0) {
		rt::print("diff: ");
		rt::printnum(dropped: u64);
		rt::println(" lines did not fit");
	};
	lib::release(ta);
	lib::release(tb);
};