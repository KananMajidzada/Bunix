use lib;
use rt;

def MAXEXTPROG: size = 16;
def ARENASZ: size = 65536;
def SCRATCHSZ: size = 1024;

// Storage for unescaping a line and for rewriting a file to append to it.
let arena: [ARENASZ]u8 = [0...];
let scratch: [SCRATCHSZ]u8 = [0...];
def MAXNAME: size = 32;

let extprog_count: size = 0;
let extprog_names: [MAXEXTPROG][MAXNAME]u8 = [[0...]...];

fn load_bin() void = {
	let buf: [512]u8 = [0...];
	const n = rt::readdir("/bin", buf[..]);
	if (n == 0) {
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			const l = i - start;
			if (l > 0 && l < MAXNAME && extprog_count < MAXEXTPROG) {
				for (let j = 0z; j < l; j += 1) {
					extprog_names[extprog_count][j] = buf[start + j];
				};
				extprog_names[extprog_count][l] = 0;
				extprog_count += 1;
			};
			start = i + 1;
		};
	};
};

fn is_extprog(cmd: []u8) bool = {
	for (let i = 0z; i < extprog_count; i += 1) {
		let ok = true;
		for (let j = 0z; j < len(cmd); j += 1) {
			if (extprog_names[i][j] != cmd[j]) {
				ok = false;
				break;
			};
		};
		if (ok && extprog_names[i][len(cmd)] == 0) {
			return true;
		};
	};
	return false;
};

fn help_extprog() void = {
	for (let i = 0z; i < extprog_count; i += 1) {
		rt::print(" ");
		let j = 0z;
		for (extprog_names[i][j] != 0) {
			rt::putc(extprog_names[i][j]);
			j += 1;
		};
	};
	rt::println("");
};

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
		load_bin();
		for (true) {
			rt::print("ush> ");
			let lb: [128]u8 = [0...];
			let n = 0z;
			for (true) {
				// Each terminal window has a shell of its own, so there is
				// no second prompt to give when another one is opened.
				const c = rt::readchr();
				if (c == 0) {
					rt::cop();
					continue;
				};
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
			const sp = lib::first_space(line);
			const cmd = line[..sp];
			const rest = if (sp < len(line)) line[sp + 1..] else line[..0];
			if (str_eq(cmd, "exit")) {
				rt::println("bye");
				break;
			} else if (str_eq(cmd, "help")) {
				rt::print("cat ls echo write mkdir touch rm hd cc user multi halt version exit");
				help_extprog();
			} else if (str_eq(cmd, "version")) {
				const vp: str = "/proc/version";
				run_cat(*(&vp: *[]u8));
			} else if (str_eq(cmd, "echo")) {
				rt::write(rest);
				rt::println("");
			} else if (str_eq(cmd, "ls")) {
				const rootpath: str = "/";
				run_ls(if (len(rest) == 0) *(&rootpath: *[]u8) else rest);
			} else if (str_eq(cmd, "cat")) {
				run_cat(rest);
			} else if (str_eq(cmd, "write")) {
				let body = rest;
				let do_append = false;
				if (len(body) >= 3 && body[0] == ('-': u8) && body[1] == ('a': u8)
						&& (body[2] == (' ': u8) || body[2] == ('\t': u8))) {
					do_append = true;
					body = body[3..];
					for (len(body) > 0 && (body[0] == (' ': u8) || body[0] == ('\t': u8))) {
						body = body[1..];
					};
				};
				const w = lib::first_space(body);
				if (w == len(body)) {
					rt::println("usage: write [-a] <path> <text>");
				} else {
					const path = body[..w];
					let raw = body[w + 1..];
					if (len(raw) >= 2) {
						const db = *(&raw: *[]u8);
						if ((db[0] == ('"': u8) && db[len(db) - 1] == ('"': u8))
								|| (db[0] == 39 && db[len(db) - 1] == 39)) {
							raw = raw[1..len(raw) - 1];
						};
					};
					const text = unescape(raw);
					let k = 0z;
					if (do_append) {
						k = append_text(*(&path: *str), text);
					} else {
						k = rt::writefile(*(&path: *str), text);
					};
					rt::print("wrote ");
					rt::printnum(k: u64);
					rt::println(" bytes");
				};
			} else if (str_eq(cmd, "hd")) {
				run_hd(rest);
			} else if (str_eq(cmd, "cc")) {
				run_cc(rest);
			} else if (str_eq(cmd, "mkdir")) {
				report(rt::mkdir(*(&rest: *str)), "created", "cannot create");
			} else if (str_eq(cmd, "touch")) {
				report(rt::create(*(&rest: *str)), "created", "cannot create");
			} else if (str_eq(cmd, "rm")) {
				report(rt::remove(*(&rest: *str)), "removed", "cannot remove");
			} else if (is_extprog(cmd)) {
				// external program with an image of its own
				run(line);
			} else if (is_path(cmd)) {
				// a path into the filesystem: the loader decides whether it
				// is an executable to run or a file to read
				run(line);
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

// Run a program in an image of its own and wait for it. The loader picks the
// image by the first word of the line.
fn run(line: []u8) void = {
	const pid = rt::spawn_shared(*(&line: *str));
	if (pid == ~0u64) {
		rt::println("cannot run");
		return;
	};
	for (rt::alive(pid)) {
		rt::cop();
	};
};

fn report(ok: bool, yes: str, no: str) void = {
	if (ok) {
		rt::println(yes);
	} else {
		rt::println(no);
	};
};

// A command naming something in the filesystem rather than a built-in. The
// loader decides whether it is an executable to run or a file to read.
fn is_path(cmd: []u8) bool = {
	if (len(cmd) == 0 || cmd[0] != ('/': u8)) {
		return false;
	};
	return rt::exists(*(&cmd: *str));
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

// Lists a directory. A directory has no contents to read as a file, so this
// goes through readdir instead.
fn run_ls(path: []u8) void = {
	let buf: [512]u8 = [0...];
	const n = rt::readdir(*(&path: *str), buf[..]);
	if (n == 0) {
		rt::print("ls: nothing in ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				for (let j = start; j < i; j += 1) {
					rt::putc(buf[j]);
				};
				rt::println("");
			};
			start = i + 1;
		};
	};
};

// Turns the escapes a person actually types at the shell into bytes. Without
// this, "write f "a\nb"" would store a backslash and an n.
fn unescape(src: []u8) []u8 = {
	let n = 0z;
	let i = 0z;
	for (i < len(src) && n < len(scratch); i += 1) {
		let c = src[i];
		if (c == ('\\': u8) && i + 1 < len(src)) {
			const e = src[i + 1];
			i += 1;
			if (e == ('n': u8)) {
				c = ('\n': u8);
			} else if (e == ('t': u8)) {
				c = ('\t': u8);
			} else if (e == ('r': u8)) {
				c = ('\r': u8);
			} else if (e == ('0': u8)) {
				c = 0;
			} else {
				c = e;
			};
		};
		scratch[n] = c;
		n += 1;
	};
	return scratch[..n];
};

// Append by rewriting: the filesystem's write always lands at offset zero, so
// the old bytes have to be carried along.
fn append_text(path: str, text: []u8) size = {
	const have = rt::readfile(path, arena[..]);
	let n = have;
	for (let i = 0z; i < len(text) && n < len(arena); i += 1) {
		arena[n] = text[i];
		n += 1;
	};
	return rt::writefile(path, arena[..n]);
};

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

// Decimal, for "hd <path> <offset>".
fn parse_num(s: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(s); i += 1) {
		if (s[i] < ('0': u8) || s[i] > ('9': u8)) {
			break;
		};
		n = n * 10 + (s[i] - ('0': u8));
	};
	return n;
};

// A hex dump, "hd <path> [offset]". Read through a heap window so it works on
// a file too large for a stack buffer, which is what a linked executable is.
fn run_hd(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: hd <path> [offset]");
		return;
	};
	const sp = lib::first_space(rest);
	const path = rest[..sp];
	let off = 0z;
	if (sp < len(rest)) {
		off = parse_num(rest[sp + 1..]);
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("hd: out of memory");
		return;
	};
	const view = (window: *[65536]u8)[..];
	const n = rt::readfile(*(&path: *str), view);
	if (n == 0) {
		rt::println("no such file");
		return;
	};
	for (let i = off; i < n; i += 16) {
		rt::putc(hexdig((i >> 12): u8 & 0x0f));
		rt::putc(hexdig((i >> 8): u8 & 0x0f));
		rt::putc(hexdig((i >> 4): u8 & 0x0f));
		rt::putc(hexdig(i: u8 & 0x0f));
		rt::print(": ");
		for (let j = 0z; j < 16 && i + j < n; j += 1) {
			const b = view[i + j];
			rt::putc(hexdig(b >> 4));
			rt::putc(hexdig(b & 0x0f));
			rt::putc(' ');
		};
		rt::println("");
	};
};

// Append one piece onto the end of a buffer.
fn put_into(out: []u8, at: *size, s: []u8) void = {
	for (let i = 0z; i < len(s) && *at < len(out); i += 1) {
		out[*at] = s[i];
		*at = *at + 1;
	};
};

// The command line for the compiler inside Bunix. tcc links against our own
// startup objects and library and must not go looking for a host system, so the
// flags are spelled out once here rather than at every prompt.
fn cc_line(args: []u8) void = {
	const head: str = "tcc ";
	const flags: str = "-static -nostdlib -B/usr/lib -L/usr/lib -I/usr/include";
	const crt1: str = " /usr/lib/crt1.o";
	const crti: str = " /usr/lib/crti.o";
	const libc: str = " /usr/lib/libc.a";
	const crtn: str = " /usr/lib/crtn.o";
	let buf: [600]u8 = [0...];
	let n = 0z;
	put_into(buf[..], &n, *(&head: *[]u8));
	put_into(buf[..], &n, *(&flags: *[]u8));
	put_into(buf[..], &n, args);
	put_into(buf[..], &n, *(&crt1: *[]u8));
	put_into(buf[..], &n, *(&crti: *[]u8));
	put_into(buf[..], &n, *(&libc: *[]u8));
	put_into(buf[..], &n, *(&crtn: *[]u8));
	run(buf[..n]);
};

// cc [-o out] source...  compiles and links against the Bunix runtime.
fn run_cc(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: cc [-o outfile] file.c ...");
		return;
	};
	const gap: str = " ";
	let outp: [256]u8 = [0...];
	let outn = 0z;
	let srcs: [400]u8 = [0...];
	let n = 0z;
	let i = 0z;
	for (true) {
		for (i < len(rest) && (rest[i] == (' ': u8) || rest[i] == ('\t': u8))) {
			i += 1;
		};
		const start = i;
		for (i < len(rest) && rest[i] != (' ': u8) && rest[i] != ('\t': u8)) {
			i += 1;
		};
		if (start == i) {
			break;
		};
		const tok = rest[start..i];
		if (len(tok) > 2 && tok[0] == ('-': u8) && (tok[1] == ('o': u8) || tok[1] == ('O': u8))) {
			const v = tok[2..];
			let k = len(v);
			if (k > len(outp)) {
				k = len(outp);
			};
			for (let j = 0z; j < k; j += 1) {
				outp[j] = v[j];
			};
			outn = k;
			continue;
		};
		put_into(srcs[..], &n, tok);
		put_into(srcs[..], &n, *(&gap: *[]u8));
	};
	if (n == 0) {
		rt::println("cc: no input files");
		return;
	};
	let args: [600]u8 = [0...];
	let an = 0z;
	const dasho: str = "-o ";
	put_into(args[..], &an, *(&dasho: *[]u8));
	put_into(args[..], &an, outp[..outn]);
	put_into(args[..], &an, *(&gap: *[]u8));
	put_into(args[..], &an, srcs[..n]);
	cc_line(args[..an]);
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