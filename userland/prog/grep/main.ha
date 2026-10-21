use lib;
use posix;
use rt;

let patbuf: [512]u8 = [0...];
let linebuf: [512]u8 = [0...];

// Print every line of a file that holds a pattern. With -i the pattern is
// matched without regard to case, with -v the lines that do not hold it are
// printed instead, with -n each line says which one it is, and with -c only
// the number of lines that hold it is printed.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let icase = false;
	let invert = false;
	let numbers = false;
	let countonly = false;
	let pos: [lib::MAXWORDS][]u8 = [[]...];
	let npos = 0z;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (len(w) > 1 && w[0] == ('-': u8)) {
			let ok = true;
			for (let j = 1z; j < len(w); j += 1) {
				if (w[j] == ('i': u8)) {
					icase = true;
				} else if (w[j] == ('v': u8)) {
					invert = true;
				} else if (w[j] == ('n': u8)) {
					numbers = true;
				} else if (w[j] == ('c': u8)) {
					countonly = true;
				} else {
					ok = false;
				};
			};
			if (ok) {
				continue;
			};
		};
		if (npos < lib::MAXWORDS) {
			pos[npos] = w;
			npos += 1;
		};
	};
	if (npos < 2) {
		rt::println("usage: grep [-ivnc] <pattern> <path>...");
		return;
	};
	// The pattern is folded once, so every line is compared against the
	// same thing.
	const pat = pos[0];
	let fpat = pat;
	if (icase) {
		fpat = patbuf[..fold(pat, patbuf)];
	};
	for (let i = 1z; i < npos; i += 1) {
		const path = pos[i];
		const fd = posix::open(*(&path: *str), posix::O_RDONLY);
		if (fd < 0) {
			rt::print("grep: cannot open ");
			rt::println(*(&path: *str));
			continue;
		};
		let buf: [512]u8 = [0...];
		let line: [512]u8 = [0...];
		let nl = 0z;
		let lineno: u64 = 0;
		let matches: u64 = 0;
		for (true) {
			const k = posix::read(fd, buf[..]);
			if (k == 0) {
				if (nl > 0) {
					emit(line[..nl], pat, fpat, icase,
						invert, numbers, countonly,
						&lineno, &matches);
				};
				break;
			};
			for (let j = 0z; j < k; j += 1) {
				line[nl] = buf[j];
				const eol = buf[j] == ('\n': u8);
				if (!eol) {
					nl += 1;
				};
				if (eol || nl == len(line)) {
					emit(line[..nl], pat, fpat, icase,
						invert, numbers, countonly,
						&lineno, &matches);
					nl = 0;
				};
			};
		};
		posix::close(fd);
		if (countonly) {
			rt::printnum(matches);
			// The name of the file is only worth saying when there
			// is more than one of them.
			if (npos > 2) {
				rt::print(" ");
				rt::write(path);
			};
			rt::println("");
		};
	};
};

// One line of a file, printed when it is a line that is wanted.
fn emit(
	line: []u8,
	pat: []u8,
	fpat: []u8,
	icase: bool,
	invert: bool,
	numbers: bool,
	countonly: bool,
	lineno: *u64,
	matches: *u64,
) void = {
	*lineno += 1;
	let hit = holds(line, pat, fpat, icase);
	if (invert) {
		hit = !hit;
	};
	if (!hit) {
		return;
	};
	*matches += 1;
	if (countonly) {
		return;
	};
	if (numbers) {
		rt::printnum(*lineno);
		rt::putc(('\t': u8));
	};
	rt::write(line);
	rt::println("");
};

// Whether a line holds the pattern. The folded copy of the pattern is only
// there when the case is being ignored.
fn holds(line: []u8, pat: []u8, fpat: []u8, icase: bool) bool = {
	if (icase) {
		return lib::contains(linebuf[..fold(line, linebuf)], fpat);
	};
	return lib::contains(line, pat);
};

// A copy of the bytes in lower case, so a pattern can be matched against
// them whatever case they were written in.
fn fold(b: []u8, out: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(b) && n < len(out); i += 1) {
		const c = b[i];
		out[n] = if (c >= ('A': u8) && c <= ('Z': u8)) c + 32 else c;
		n += 1;
	};
	return n;
};
