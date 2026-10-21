use lib;
use posix;
use rt;

// Number the bytes, the lines, and the words of a file. With more than one
// file the numbers for each are shown, and then the total.
//
// The flags say which numbers to show: -l for the lines, -w for the words
// and -c for the bytes. Without any of them, all three are shown.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const line = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(line, &words);
	let show_lines = false;
	let show_words = false;
	let show_bytes = false;
	let first = 0z;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (i == 0 && len(w) > 1 && w[0] == ('-': u8)) {
			// The flags come before the names of the files.
			let ok = true;
			for (let j = 1z; j < len(w); j += 1) {
				if (w[j] == ('l': u8)) {
					show_lines = true;
				} else if (w[j] == ('w': u8)) {
					show_words = true;
				} else if (w[j] == ('c': u8)) {
					show_bytes = true;
				} else {
					ok = false;
				};
			};
			if (ok) {
				continue;
			};
			// Not a flag after all, so it is a name of a file.
			first = 0z;
			break;
		};
		first = i;
		break;
	};
	if (!show_lines && !show_words && !show_bytes) {
		show_lines = true;
		show_words = true;
		show_bytes = true;
	};
	if (n <= first) {
		rt::println("usage: wc [-lwc] <path>...");
		return;
	};
	let tb = 0u64, tl = 0u64, tw = 0u64;
	for (let i = first; i < n; i += 1) {
		const path = words[i];
		const fd = posix::open(*(&path: *str), posix::O_RDONLY);
		if (fd < 0) {
			rt::print("wc: cannot open ");
			rt::println(*(&path: *str));
			continue;
		};
		let buf: [512]u8 = [0...];
		let bytes = 0u64, lines = 0u64, wds = 0u64;
		let inword = false;
		for (true) {
			const k = posix::read(fd, buf[..]);
			if (k == 0) {
				break;
			};
			for (let j = 0z; j < k; j += 1) {
				const c = buf[j];
				bytes += 1;
				if (c == ('\n': u8)) {
					lines += 1;
				};
				if (c == (' ': u8) || c == ('\n': u8) || c == ('\t': u8)) {
					inword = false;
				} else if (!inword) {
					inword = true;
					wds += 1;
				};
			};
		};
		posix::close(fd);
		tb += bytes;
		tl += lines;
		tw += wds;
		// The name of the file is worth saying when there is more than
		// one of them, and the file a pipe made is not worth naming.
		const named = n - first > 1 || !is_pipe(path);
		show(show_lines, show_words, show_bytes, lines, wds, bytes, path, named);
	};
	if (n - first > 1) {
		show(show_lines, show_words, show_bytes, tl, tw, tb,
			*(&"total": *[]u8), true);
	};
};

// Whether a file is the one a pipe put a command's output in.
fn is_pipe(name: []u8) bool = {
	const prefix = *(&"/dev/pipe": *[]u8);
	if (len(name) < len(prefix)) {
		return false;
	};
	for (let i = 0z; i < len(prefix); i += 1) {
		if (name[i] != prefix[i]) {
			return false;
		};
	};
	return true;
};

fn show(
	sl: bool,
	sw: bool,
	sc: bool,
	lines: u64,
	words: u64,
	bytes: u64,
	name: []u8,
	named: bool,
) void = {
	let any = false;
	if (sl) {
		rt::printnum(lines);
		any = true;
	};
	if (sw) {
		if (any) {
			rt::print(" ");
		};
		rt::printnum(words);
		any = true;
	};
	if (sc) {
		if (any) {
			rt::print(" ");
		};
		rt::printnum(bytes);
		any = true;
	};
	if (named) {
		if (any) {
			rt::print(" ");
		};
		rt::write(name);
	};
	rt::println("");
};
