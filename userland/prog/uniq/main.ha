use lib;
use rt;

// Drops the lines that are the same as the one before them. Only neighbours
// are compared, so a file that is already in order loses only the repeats.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: uniq <path>");
		return;
	};
	const path = words[0];
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("uniq: out of memory");
		return;
	};
	const buf = (window: *[65536]u8)[..];
	const flen = rt::readfile(*(&path: *str), buf);
	if (flen == 0) {
		rt::print("uniq: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	let pstart = 0z;
	let plast = 0z;
	let have = false;
	for (let i = 0z; i <= flen; i += 1) {
		if (i == flen || buf[i] == ('\n': u8)) {
			if (i == flen && start == flen) {
				break;
			};
			const llen = i - start;
			if (have && llen == plast && same(buf, pstart, plast, start, llen)) {
				// The same as the line before it, so it goes.
				start = i + 1;
				continue;
			};
			rt::write(buf[start..start + llen]);
			rt::println("");
			pstart = start;
			plast = llen;
			have = true;
			start = i + 1;
		};
	};
};

// Whether two runs of bytes in the buffer are the same.
fn same(buf: []u8, ao: size, al: size, bo: size, bl: size) bool = {
	if (al != bl) {
		return false;
	};
	for (let i = 0z; i < al; i += 1) {
		if (buf[ao + i] != buf[bo + i]) {
			return false;
		};
	};
	return true;
};
