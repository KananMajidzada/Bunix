use lib;
use rt;

// fold [-w width] [file]
//
// Breaks long lines into shorter ones. A line has no end in a file but does on
// a screen, and folding is how a wide listing is made to fit eighty columns
// without editing it.
//
// The break goes at a space where there is one, so words stay whole; a line
// with no space in it is cut where it has to be.

let width: size = 80;

fn folded(line: []u8) bool = {
	if (len(line) <= width) {
		rt::println(*(&line: *str));
		return true;
	};
	// Where the line last had room to break, and where the last one ended.
	let last: size = 0;
	let start = 0z;
	for (let i = 0z; i <= len(line); i += 1) {
		if (i < len(line) && !lib::is_space(line[i])) {
			continue;
		};
		if (i - start >= width && last > start) {
			rt::println(*(&line[start..last]: *str));
			start = last;
			// The space that was the break is dropped rather than starting
			// the next line with a blank.
			for (let k = 0z; start < i && lib::is_space(line[start]); k += 1) {
				start += 1;
			};
		};
		if (i < len(line)) {
			last = i;
		};
	};
	if (start < len(line)) {
		rt::println(*(&line[start..]: *str));
	};
	return true;
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) > 1 && tok[1] == ('w': u8)) {
			let (v, next) = lib::flag_val(args, pos, 2, width: u64);
			if (v < 4) {
				v = 4;
			};
			width = v: size;
			pos = next;
			continue;
		};
		rt::print("fold: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		const text = lib::slurp(path);
		if (len(text) == 0) {
			rt::print("fold: cannot read ");
			rt::println(*(&path: *str));
			nfiles += 1;
			pos = next;
			continue;
		};
		lib::each_line(text, &folded);
		lib::release(text);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: fold [-w width] [file]");
	};
};