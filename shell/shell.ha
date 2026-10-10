use arch;
use bfp;
use console;
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
		console::println("commands: help, version, echo, clear, mem, frames, uptime, bfp, heap, spawn, threads, fault, halt");
	} else if (eq(line, "version")) {
		console::print(sys::NAME);
		console::print(" ");
		console::println(sys::VERSION);
	} else if (prefix(line, "echo ")) {
		console::write(line[len("echo ")..]);
		console::putc('\n': u8);
	} else if (eq(line, "clear")) {
		console::clear();
	} else if (eq(line, "bfp")) {
		let srv = bfp::new("hello from the Bunix File Protocol\n");
		const data = bfp::slurp(&srv, "hello");
		console::print("bfp: ");
		console::write(data);
	} else if (eq(line, "heap")) {
		heap_demo();
	} else if (eq(line, "spawn")) {
		spawn_workers();
	} else if (eq(line, "threads")) {
		show_threads();
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
		console::printnum(arch::seconds());
		console::println(" s");
	} else if (eq(line, "fault")) {
		console::println("touching an unmapped address");
		_ = arch::probe(0x100000000);
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
		arch::pause();
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
	console::printnum(sched::count());
	console::putc('\n');
	for (let i = 0z; i < NWORKERS; i += 1) {
		console::print("worker ");
		console::printnum(i);
		console::print(": ");
		console::printnum(counters[i]);
		console::putc('\n');
	};
};
