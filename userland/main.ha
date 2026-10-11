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

	if (rt::strcmp(a, "/ns")) {
		rt::println("namespace view of / :");
		let out: [256]u8 = [0...];
		let k = rt::readfile("/", out[..]);
		rt::write(out[..k]);
		const marker: str = "sealed with a private marker\n";
		_ = rt::create("/pp");
		_ = rt::writefile("/pp", *(&marker: *[]u8));
		k = rt::readfile("/pp", out[..]);
		rt::print("read back: ");
		rt::write(out[..k]);
		k = rt::readfile("/hello", out[..]);
		rt::print("shared /hello bytes: ");
		rt::printnum(k: u64);
		rt::println("");
		k = rt::readfile("/proc/self", out[..]);
		rt::print("this process: ");
		rt::write(out[..k]);
		return;
	};

	if (rt::strcmp(a, "/disk")) {
		let out: [512]u8 = [0...];
		const k = rt::readfile("/dev/disk", out[..]);
		rt::print("sector 0 holds ");
		rt::printnum(k: u64);
		rt::print(" bytes: ");
		let n = 0z;
		for (n < k && out[n] != ('\n': u8) && out[n] != 0) {
			rt::putc(out[n]);
			n += 1;
		};
		rt::println("");
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
		rt::println("bunix user shell, type 'help'");
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
			if (len(line) == 0) {
				continue;
			};
			const sp = first_space(line);
			const cmd = line[..sp];
			const rest = if (sp < len(line)) line[sp + 1..] else line[..0];
			if (str_eq(cmd, "exit")) {
				rt::println("bye");
				break;
			} else if (str_eq(cmd, "help")) {
				rt::println("cat ls echo write mkdir touch rm user multi halt version exit");
			} else if (str_eq(cmd, "version")) {
				const vp: str = "/proc/version";
				run_cat(*(&vp: *[]u8));
			} else if (str_eq(cmd, "echo")) {
				rt::write(rest);
				rt::println("");
			} else if (str_eq(cmd, "ls")) {
				const rootpath: str = "/";
				run_cat(if (len(rest) == 0) *(&rootpath: *[]u8) else rest);
			} else if (str_eq(cmd, "cat")) {
				run_cat(rest);
			} else if (str_eq(cmd, "write")) {
				const w = first_space(rest);
				if (w == len(rest)) {
					rt::println("usage: write <path> <text>");
				} else {
					const k = rt::writefile(*(&rest[..w]: *str), rest[w + 1..]);
					rt::print("wrote ");
					rt::printnum(k: u64);
					rt::println(" bytes");
				};
			} else if (str_eq(cmd, "mkdir")) {
				report(rt::mkdir(*(&rest: *str)), "created", "cannot create");
			} else if (str_eq(cmd, "touch")) {
				report(rt::create(*(&rest: *str)), "created", "cannot create");
			} else if (str_eq(cmd, "rm")) {
				report(rt::remove(*(&rest: *str)), "removed", "cannot remove");
			} else if (str_eq(cmd, "user")) {
				const pid = rt::spawn(*(&rest: *str));
				if (pid == ~0u64) {
					rt::println("cannot spawn");
				} else {
					for (rt::alive(pid)) {
						rt::cop();
					};
					rt::println("user process exited");
				};
			} else if (str_eq(cmd, "multi")) {
				let ids: [3]u64 = [0u64, 0u64, 0u64];
				for (let i = 0z; i < 3; i += 1) {
					let arg: [8]u8 = [0...];
					arg[0] = '/': u8;
					arg[1] = 's': u8;
					arg[2] = 'p': u8;
					arg[3] = 'i': u8;
					arg[4] = 'n': u8;
					arg[5] = ' ': u8;
					arg[6] = ('1': u8) + (i: u8);
					const s = *(&arg[..7]: *str);
					ids[i] = rt::spawn(s);
				};
				for (true) {
					let live = false;
					for (let i = 0z; i < 3; i += 1) {
						if (rt::alive(ids[i])) {
							live = true;
						};
					};
					if (!live) {
						break;
					};
					rt::cop();
				};
				rt::println("all user processes exited");
			} else if (str_eq(cmd, "halt")) {
				rt::print("halting. ");
				rt::haltsys();
			} else {
				rt::print("unknown command: ");
				rt::println(*(&cmd: *str));
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

fn first_space(b: []u8) size = {
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == (' ': u8)) {
			return i;
		};
	};
	return len(b);
};

fn report(ok: bool, yes: str, no: str) void = {
	if (ok) {
		rt::println(yes);
	} else {
		rt::println(no);
	};
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
