use lib;
use posix;
use rt;

// Number the bytes, the lines, and the words of a file. With more than one
// file the numbers for each are shown, and then the total.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const line = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(line, &words);
	if (n < 1) {
		rt::println("usage: wc <path>...");
		return;
	};
	let tb = 0u64, tl = 0u64, tw = 0u64;
	for (let i = 0z; i < n; i += 1) {
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
		show(lines, wds, bytes, path);
	};
	if (n > 1) {
		show(tl, tw, tb, *(&"total": *[]u8));
	};
};

fn show(lines: u64, words: u64, bytes: u64, name: []u8) void = {
	rt::printnum(lines);
	rt::print(" ");
	rt::printnum(words);
	rt::print(" ");
	rt::printnum(bytes);
	rt::print(" ");
	rt::println(*(&name: *str));
};
