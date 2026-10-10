use rt;

export @symbol("main") fn main() void = {
	const a = rt::arg();
	if (len(a) == 0) {
		rt::println("usage: cat <path>");
		return;
	};

	if (rt::strcmp(a, "/heap")) {
		let b: []u8 = [];
		for (let i = 0z; i < 8; i += 1) {
			append(b, ('A': u8) + (i: u8))!;
		};
		rt::print("heap: ");
		rt::write(b);
		rt::println("");
		free(b);
		return;
	};

	if (rt::strcmp(a, "/bad")) {
		rt::println("touching supervisor memory");
		const addr = 0x100000: uintptr;
		const p = addr: *u64;
		*p = 1;
		rt::println("should not reach here");
		return;
	};

	if (rt::strcmp(a, "/cons")) {
		const s: str = "written through /dev/cons\n";
		_ = rt::writefile("/dev/cons", *(&s: *[]u8));
		return;
	};

	if (rt::strcmp(a, "/note")) {
		const s: str = "a note from a user process\n";
		_ = rt::writefile("/dev/note", *(&s: *[]u8));
		let out: [256]u8 = [0...];
		const k = rt::readfile("/dev/note", out[..]);
		rt::print("note: ");
		rt::write(out[..k]);
		return;
	};

	if (starts(a, "/spin ")) {
		for (let i = 0u64; i < 4; i += 1) {
			rt::print(a);
			rt::print(" step ");
			rt::printnum(i);
			rt::println("");
			for (let j = 0u64; j < 4000000; j += 1) {
				void;
			};
		};
		return;
	};

	if (rt::strcmp(a, "/sh")) {
		rt::println("bunix user shell, type 'exit'");
		for (true) {
			rt::print("ush> ");
			let lb: [128]u8 = [0...];
			let n = 0z;
			for (true) {
				const c = rt::getchar();
				if (c == ('\n': u8) || c == ('\r': u8)) {
					rt::println("");
					break;
				};
				if (c == 8 || c == 127) {
					if (n > 0) {
						n -= 1;
						rt::print("\b \b");
					};
					continue;
				};
				if (n < 127) {
					lb[n] = c;
					n += 1;
					rt::putc(c);
				};
			};
			const line = *(&lb[..n]: *[]u8);
			if (str_eq(line, "exit")) {
				rt::println("bye");
				break;
			};
			if (len(line) == 0) {
				continue;
			};
			if (starts2(line, "cat ")) {
				run_cat(line[4..]);
			} else if (starts2(line, "ls ")) {
				run_cat(line[3..]);
			} else {
				run_cat(line);
			};
		};
		return;
	};

	let buf: [256]u8 = [0...];
	const n = rt::readfile(a, buf[..]);
	if (n == 0) {
		rt::print("cat: cannot read ");
		rt::println(a);
		return;
	};
	rt::write(buf[..n]);
};

fn starts(s: str, p: str) bool = {
	const b = *(&s: *[]u8);
	const pb = *(&p: *[]u8);
	if (len(b) < len(pb)) {
		return false;
	};
	for (let i = 0z; i < len(pb); i += 1) {
		if (b[i] != pb[i]) {
			return false;
		};
	};
	return true;
};

fn starts2(b: []u8, p: str) bool = {
	const pb = *(&p: *[]u8);
	if (len(b) < len(pb)) {
		return false;
	};
	for (let i = 0z; i < len(pb); i += 1) {
		if (b[i] != pb[i]) {
			return false;
		};
	};
	return true;
};

fn str_eq(b: []u8, s: str) bool = {
	const sb = *(&s: *[]u8);
	if (len(b) != len(sb)) {
		return false;
	};
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] != sb[i]) {
			return false;
		};
	};
	return true;
};

fn run_cat(path: []u8) void = {
	let buf: [512]u8 = [0...];
	const n = rt::readfile(*(&path: *str), buf[..]);
	if (n == 0) {
		rt::println("no such file");
		return;
	};
	rt::write(buf[..n]);
	if (buf[n - 1] != ('\n': u8)) {
		rt::println("");
	};
};
