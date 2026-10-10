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

	let buf: [256]u8 = [0...];
	const n = rt::readfile(a, buf[..]);
	if (n == 0) {
		rt::print("cat: cannot read ");
		rt::println(a);
		return;
	};
	rt::write(buf[..n]);
};
