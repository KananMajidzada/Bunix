use architecture;
use console;
use fs;
use loader;
use mem;
use rt;
use sched;
use sys;

def BUFSZ: size = 256;

export fn run(mem_mib: u64) never = {
	let line: [BUFSZ]u8 = [0...];
	for (true) {
		console::print("bunix> ");
		const n = readline(line[..]);
		if (n > 0) {
			exec(mem_mib, line[..n]);
		};
	};
};

export fn monitor(id: size) never = {
	for (true) {
		if (!sched::alive(id)) {
			console::println("init exited, restarting");
			id = loader::run("/sh");
		};
		console::poll_mouse();
		architecture::pause();
	};
};

fn readline(buf: []u8) size = {
	let n = 0z;
	for (true) {
		const ch = console::getch();
		if (ch == '\n' || ch == '\r') {
			console::putc('\n': u8);
			return n;
		} else if (ch == '\b') {
			if (n > 0) {
				n -= 1;
				console::print("\b \b");
			};
		} else if (ch >= ' ' && ch < 0x7F) {
			if (n < len(buf)) {
				buf[n] = ch;
				n += 1;
				console::putc(ch);
			};
		};
	};
};

fn exec(mem_mib: u64, line: []u8) void = {
	if (eq(line, "help")) {
		console::println("commands: help, version, echo, clear, ls, cat, write, mkdir, touch, rm, mem, frames, uptime, files, heap, spawn, threads, user [path], multi, sh, fault, halt");
	} else if (eq(line, "version")) {
		sys::banner();
		console::print(sys::NAME);
		console::print(" ");
		console::println(sys::VERSION);
	} else if (prefix(line, "echo ")) {
		console::write(line[len("echo ")..]);
		console::putc('\n': u8);
	} else if (eq(line, "clear")) {
		console::clear();
	} else if (eq(line, "ls")) {
		list("/");
	} else if (prefix(line, "ls ")) {
		list(*(&line[3..]: *str));
	} else if (prefix(line, "cat ")) {
		cat(*(&line[4..]: *str));
	} else if (prefix(line, "write ")) {
		write_cmd(*(&line[6..]: *str));
	} else if (prefix(line, "mkdir ")) {
		mkdir_cmd(*(&line[6..]: *str));
	} else if (prefix(line, "touch ")) {
		touch_cmd(*(&line[6..]: *str));
	} else if (prefix(line, "rm ")) {
		rm_cmd(*(&line[3..]: *str));
	} else if (eq(line, "files")) {
		files_demo();
	} else if (eq(line, "heap")) {
		heap_demo();
	} else if (eq(line, "spawn")) {
		spawn_workers();
	} else if (eq(line, "threads")) {
		show_threads();
	} else if (eq(line, "user")) {
		run_user("/proc/version");
	} else if (prefix(line, "user ")) {
		run_user(*(&line[5..]: *str));
	} else if (eq(line, "multi")) {
		multi();
	} else if (eq(line, "sh")) {
		run_user("/sh");
	} else if (eq(line, "mem")) {
		console::print("available: ");
		console::printnum(mem_mib);
		console::println(" MiB");
	} else if (eq(line, "frames")) {
		console::printnum(mem::free_frames());
		console::print(" free of ");
		console::printnum(mem::total_frames());
		console::println(" frames");
	} else if (eq(line, "uptime")) {
		console::printnum(architecture::seconds());
		console::println(" s");
	} else if (eq(line, "fault")) {
		console::println("touching an unmapped address");
		_ = architecture::probe(0x100000000);
	} else if (eq(line, "halt")) {
		rt::halt();
	} else {
		console::print("unknown command: ");
		console::write(line);
		console::putc('\n': u8);
	};
};

// Compares a line buffer with a literal through rt::strcmp.
fn eq(line: []u8, s: str) bool = {
	let a = *(&line: *str);
	return a == s;
};

fn prefix(line: []u8, s: str) bool = {
	if (len(line) < len(s)) {
		return false;
	};
	let a = *(&line[..len(s)]: *str);
	return a == s;
};

fn list(path: str) void = {
	console::write(fs::cat(path));
};

fn cat(path: str) void = {
	if (!fs::exists(path)) {
		console::println("no such file");
		return;
	};
	console::write(fs::cat(path));
};

fn write_cmd(args: str) void = {
	const b = *(&args: *[]u8);
	let sp = 0z;
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == (' ': u8)) {
			sp = i;
			break;
		};
	};
	if (sp == 0) {
		console::println("usage: write <path> <text>");
		return;
	};
	const path = *(&b[0..sp]: *str);
	const data = *(&b[sp + 1..]: *str);
	const n = fs::write_file(path, *(&data: *[]u8));
	console::print("wrote ");
	console::printnum(n: u64);
	console::println(" bytes");
};

fn mkdir_cmd(path: str) void = {
	if (fs::create(path, true)) {
		console::println("created");
	} else {
		console::println("cannot create");
	};
};

fn touch_cmd(path: str) void = {
	if (fs::create(path, false)) {
		console::println("created");
	} else {
		console::println("cannot create");
	};
};

fn rm_cmd(path: str) void = {
	if (fs::remove(path)) {
		console::println("removed");
	} else {
		console::println("cannot remove");
	};
};

fn files_demo() void = {
	console::print("ls /:\n");
	console::write(fs::cat("/"));
	console::print("cat /proc/version: ");
	console::write(fs::cat("/proc/version"));
	console::print("cat /proc/uptime: ");
	console::write(fs::cat("/proc/uptime"));
};

fn heap_demo() void = {
	let b: []u8 = [];
	for (let i = 0; i < 26; i += 1) {
		append(b, (97 + i): u8)!;
	};
	console::print("heap: ");
	console::write(b);
	console::putc('\n');
	console::print("length: ");
	console::printnum(len(b));
	console::putc('\n');
	free(b);
};

def NWORKERS: size = 4;

let counters: [NWORKERS]u64 = [0...];
let spawned: bool = false;

fn worker(arg: uintptr) void = {
	const i = arg: size;
	for (true) {
		counters[i] += 1;
		architecture::pause();
	};
};

fn spawn_workers() void = {
	if (spawned) {
		console::println("workers already running");
		return;
	};
	let ok = true;
	for (let i = 0z; i < NWORKERS; i += 1) {
		if (!sched::spawn(&worker, i: uintptr)) {
			ok = false;
		};
	};
	spawned = ok;
	if (ok) {
		console::println("started four worker threads");
	} else {
		console::println("could not start every worker");
	};
};

fn show_threads() void = {
	console::print("threads: ");
	console::printnum(sched::live());
	console::putc('\n');
	for (let i = 0z; i < NWORKERS; i += 1) {
		console::print("worker ");
		console::printnum(i);
		console::print(": ");
		console::printnum(counters[i]);
		console::putc('\n');
	};
};

fn run_user(path: str) void = {
	const id = loader::run(path);
	if (id == sched::NOID) {
		console::println("could not start the user process");
		return;
	};
	for (sched::alive(id)) {
		architecture::pause();
	};
	console::println("user process exited");
};

fn multi() void = {
	let ids: [3]size = [sched::NOID, sched::NOID, sched::NOID];
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
		ids[i] = loader::run(s);
	};
	let live = true;
	for (live) {
		live = false;
		for (let i = 0z; i < 3; i += 1) {
			if (sched::alive(ids[i])) {
				live = true;
			};
		};
		architecture::pause();
	};
	console::println("all user processes exited");
};
