use lib;
use rt;

def MAXFILES: size = 4;
def MAXLINES: size = 512;

// Puts the lines of two or more files side by side, separated by a tab. The
// lines of the first file are the ones that go on longest: a line of a later
// file with no partner of its own is left out.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 2) {
		rt::println("usage: paste <path> <path>...");
		return;
	};
	// The lines of each file are found, so the files can be walked
	// together.
	for (let i = 0z; i < n && i < MAXFILES; i += 1) {
		const path = words[i];
		const window = rt::page_alloc(4);
		if (window == 0) {
			rt::println("paste: out of memory");
			return;
		};
		const buf = (window: *[16384]u8)[..];
		const flen = rt::readfile(*(&path: *str), buf);
		if (flen == 0) {
			rt::print("paste: cannot read ");
			rt::println(*(&path: *str));
			continue;
		};
		bufs[i] = buf;
		lens[i] = flen;
		// The lines of the file are found, and where each one starts.
		let start = 0z;
		for (let j = 0z; j <= flen; j += 1) {
			if (j == flen || buf[j] == ('\n': u8)) {
				if (j == flen && start == flen) {
					break;
				};
				if (counts[i] < MAXLINES) {
					starts[i][counts[i]] = start;
					counts[i] += 1;
				};
				start = j + 1;
			};
		};
	};
	// The longest file decides how many lines there are.
	let rows = 0z;
	for (let i = 0z; i < n && i < MAXFILES; i += 1) {
		if (counts[i] > rows) {
			rows = counts[i];
		};
	};
	for (let r = 0z; r < rows; r += 1) {
		let first = true;
		for (let i = 0z; i < n && i < MAXFILES; i += 1) {
			if (counts[i] == 0 || r >= counts[i]) {
				continue;
			};
			if (!first) {
				rt::putc('\t');
			};
			first = false;
			const s = starts[i][r];
			// The end of the line is the newline, or the end of the file.
			let e = s;
			for (e < lens[i] && bufs[i][e] != ('\n': u8)) {
				e += 1;
			};
			rt::write(bufs[i][s..e]);
		};
		rt::println("");
	};
};

// The files being pasted, and where the lines of each one are.
let bufs: [MAXFILES][]u8 = [[]...];
let lens: [MAXFILES]size = [0...];
let starts: [MAXFILES][MAXLINES]size = [[0...], [0...], [0...], [0...]];
let counts: [MAXFILES]size = [0...];
