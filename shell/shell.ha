use architecture;
use block;
use console;
use fs;
use loader;
use mem;
use rt;
use sched;
use sys;

def BUFSZ: size = 256;

// The tree walk below keeps one listing and one path per level of depth.
// Sharing them would be smaller, but the recursion writes over the level that
// is walking, and the filesystem is deeper than four.
def MAXDEPTH: size = 12;
def DIRCAP: size = 1024;
def PATHCAP: size = 128;
def INDENT: size = 2;

let lbuf: [MAXDEPTH][DIRCAP]u8 = [[0...]...];
let llen: [MAXDEPTH]size = [0...];
let pbuf: [MAXDEPTH][PATHCAP]u8 = [[0...]...];
let plen: [MAXDEPTH]size = [0...];

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

// Watches the userland init. When the init process will not start at all
// there is no userland shell to type at, so the kernel's own one takes over:
// a system that cannot run its userland should still answer a question about
// its memory and its files rather than sit at a blank screen.
export fn monitor(id: size, mem_mib: u64) never = {
	for (true) {
		if (!sched::alive(id)) {
			console::println("init exited, restarting");
			const next = loader::run("/sh");
			if (next == sched::NOID) {
				console::println("userland will not start, falling back to the kernel shell");
				run(mem_mib);
			};
			id = next;
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

// The first blank and what follows it, so a command and its arguments come
// apart in the same way the userland shell takes them.
fn cut(line: []u8) ([]u8, []u8) = {
	let sp = len(line);
	for (let i = 0z; i < len(line); i += 1) {
		if (line[i] == (' ': u8) || line[i] == ('\t': u8)) {
			sp = i;
			break;
		};
	};
	if (sp >= len(line)) {
		return (line, line[..0]);
	};
	// Step over the whole run of blanks. Stopping on the first of them instead
	// leaves the arguments with a blank still in front, which is not a path
	// anything can be found by.
	let start = sp;
	for (let i = sp; i < len(line); i += 1) {
		if (line[i] != (' ': u8) && line[i] != ('\t': u8)) {
			break;
		};
		start = i + 1;
	};
	return (line[..sp], line[start..]);
};

fn name_of(line: []u8) str = {
	const p = *(&line: *str);
	if (len(p) == 0) {
		return slash();
	};
	return p;
};

fn slash() str = {
	return "/";
};

fn exec(mem_mib: u64, line: []u8) void = {
	let (cmd, rest) = cut(line);
	if (eq(cmd, "help") || eq(cmd, "man")) {
		help();
	} else if (eq(cmd, "version") || eq(cmd, "uname")) {
		sys::banner();
		console::print(sys::NAME);
		console::print(" ");
		console::println(sys::VERSION);
	} else if (prefix(line, "echo ")) {
		console::write(line[len("echo ")..]);
		console::putc('\n': u8);
	} else if (eq(cmd, "clear")) {
		console::clear();
	} else if (eq(cmd, "pwd")) {
		// There is no chdir behind this, so a process always sits at the
		// root and that is the whole of what pwd can say.
		console::println("/");
	} else if (eq(cmd, "banner")) {
		sys::banner();
	} else if (eq(cmd, "ls")) {
		list("/");
	} else if (prefix(line, "ls ")) {
		list(name_of(rest));
	} else if (eq(cmd, "tree")) {
		tree(name_of(rest));
	} else if (eq(cmd, "find")) {
		find(name_of(rest));
	} else if (eq(cmd, "stat")) {
		stat(name_of(rest));
	} else if (eq(cmd, "du")) {
		usage_of(name_of(rest));
	} else if (prefix(line, "cat ")) {
		cat(name_of(rest));
	} else if (prefix(line, "write ")) {
		write_cmd(name_of(rest));
	} else if (prefix(line, "mkdir ")) {
		mkdir_cmd(name_of(rest));
	} else if (prefix(line, "touch ")) {
		touch_cmd(name_of(rest));
	} else if (prefix(line, "rm ")) {
		rm_cmd(name_of(rest));
	} else if (eq(line, "files")) {
		files_demo();
	} else if (eq(line, "heap")) {
		heap_demo();
	} else if (eq(line, "spawn")) {
		spawn_workers();
	} else if (eq(cmd, "threads") || eq(cmd, "ps")) {
		show_threads();
	} else if (eq(cmd, "user")) {
		run_user("/proc/version");
	} else if (prefix(line, "user ")) {
		run_user(name_of(rest));
	} else if (eq(line, "multi")) {
		multi();
	} else if (eq(line, "sh")) {
		run_user("/sh");
	} else if (eq(cmd, "mem") || eq(cmd, "free")) {
		free_mem(mem_mib);
	} else if (eq(line, "frames")) {
		console::printnum(mem::free_frames());
		console::print(" free of ");
		console::printnum(mem::total_frames());
		console::println(" frames");
	} else if (eq(cmd, "df")) {
		disk_free();
	} else if (eq(cmd, "uptime") || eq(cmd, "date")) {
		console::printnum(architecture::seconds());
		console::println(" s");
	} else if (eq(line, "screen")) {
		console::printnum(console::screen_rows(): u64);
		console::print(" rows by ");
		console::printnum(console::screen_cols(): u64);
		console::println(" columns");
	} else if (eq(line, "fault")) {
		console::println("touching an unmapped address");
		_ = architecture::probe(0x100000000);
	} else if (eq(line, "halt")) {
		rt::halt();
	} else if (eq(line, "reboot")) {
		// Let the serial line go quiet first: a reset loses whatever is
		// still in the port, and this is a command somebody typed.
		console::serial_flush();
		rt::reboot();
	} else {
		console::print("unknown command: ");
		console::write(line);
		console::putc('\n': u8);
	};
};

fn help() void = {
	console::println("bunix kernel shell");
	row("help", "this");
	row("version uname banner", "what the system is");
	row("ls [path]", "list a directory");
	row("tree [path]", "a directory and everything under it");
	row("find [path]", "every file under a path");
	row("stat <path>", "what a path is");
	row("du <path>", "how much a tree holds");
	row("cat <path>", "read a file");
	row("write <path> <text>", "write a file");
	row("mkdir <path>", "make a directory");
	row("touch <path>", "make an empty file");
	row("rm <path>", "remove a file");
	row("pwd clear", "where you are, wipe the screen");
	row("mem free frames", "memory");
	row("df", "the disk");
	row("uptime date screen", "the clock and the console");
	row("threads ps", "what is running");
	row("files heap spawn", "filesystem and heap demos");
	row("sh user [path] multi", "start the userland shell");
	row("fault", "touch an unmapped address and die");
	row("halt", "stop the machine");
	row("reboot", "start it again");
	console::println("");
	console::println("ush> is the userland shell, and has the filters:");
	console::println("wc grep cp head tail sort uniq cut tr nl tac rev strings");
	console::println("tee seq mv stat tree find du cmp basename which uname free");
	console::println("nproc ps uptime date sleep");
};

// Two spaces, the name, then enough blanks to reach a fixed column. Padding by
// a fixed count would put every description a different place along.
fn row(a: str, b: str) void = {
	const ab = *(&a: *[]u8);
	let pad: size = 1;
	if (len(ab) < 24) {
		pad = 24 - len(ab);
	};
	console::print("  ");
	console::print(a);
	for (let i = 0z; i < pad; i += 1) {
		console::putc(' ': u8);
	};
	console::println(b);
};

fn list(path: str) void = {
	if (!fs::exists(path)) {
		console::println("no such path");
		return;
	};
	console::write(fs::cat(path));
};

// Writes dir + "/" + name into the next level's slot and says how long it is.
fn setpath(d: size, dir: []u8, name: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n < PATHCAP; i += 1) {
		pbuf[d][n] = dir[i];
		n += 1;
	};
	if (n > 0 && pbuf[d][n - 1] != ('/': u8)) {
		pbuf[d][n] = '/': u8;
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < PATHCAP; i += 1) {
		pbuf[d][n] = name[i];
		n += 1;
	};
	plen[d] = n;
	return n;
};

fn pad(d: size) void = {
	for (let i = 0z; i < d * INDENT; i += 1) {
		console::putc(' ': u8);
	};
};

fn isdir(path: []u8) bool = {
	let st = fs::filestat { length = 0, isdir = false };
	if (!fs::stat(*(&path: *str), &st)) {
		return false;
	};
	return st.isdir;
};

fn size_of(path: []u8) u64 = {
	let st = fs::filestat { length = 0, isdir = false };
	if (!fs::stat(*(&path: *str), &st)) {
		return 0;
	};
	return st.length;
};

fn load(d: size, path: []u8) void = {
	// fs::cat hands back a slice into a buffer the filesystem owns and reuses,
	// so the listing is copied out before anything else can ask for one.
	const list = fs::cat(*(&path: *str));
	llen[d] = len(list);
	let n = if (len(list) < DIRCAP) len(list) else DIRCAP;
	for (let i = 0z; i < n; i += 1) {
		lbuf[d][i] = list[i];
	};
};

// The name starting at `at`, and where the next one begins.
fn name_at(list: []u8, at: size) ([]u8, size) = {
	let end = at;
	for (let i = at; i < len(list) && list[i] != ('\n': u8); i += 1) {
		end = i + 1;
	};
	if (end >= len(list)) {
		return (list[at..], len(list));
	};
	return (list[at..end], end + 1);
};

// Puts the path a walk starts at into its first slot.
fn seed(root: []u8) void = {
	for (let i = 0z; i < len(root) && i < PATHCAP; i += 1) {
		pbuf[0][i] = root[i];
	};
	plen[0] = if (len(root) < PATHCAP) len(root) else PATHCAP;
};

fn tree(path: str) void = {
	if (!fs::exists(path)) {
		console::println("no such path");
		return;
	};
	const root = *(&path: *[]u8);
	// The walk builds each child's path from the one above it, so the place
	// it starts has to be in the first slot. Without this every name below
	// the top comes out on its own and finds nothing.
	seed(root);
	console::write(root);
	console::println("/");
	load(0, root);
	walk(0);
};

fn walk(d: size) void = {
	// One level below this one is the first thing the walk touches.
	if (d + 1 >= MAXDEPTH) {
		console::print("... ");
		console::write(pbuf[d][..plen[d]]);
		console::println(" (deeper)");
		return;
	};
	const list = lbuf[d][..llen[d]];
	let at = 0z;
	for (let k = 0z; at < len(list); k += 1) {
		let (name, next) = name_at(list, at);
		at = next;
		if (len(name) == 0) {
			continue;
		};
		const n = setpath(d + 1, pbuf[d][..plen[d]], name);
		const child = pbuf[d + 1][..n];
		pad(d + 1);
		console::write(name);
		if (isdir(child)) {
			console::println("/");
			load(d + 1, child);
			walk(d + 1);
		} else {
			console::print("  ");
			console::printnum(size_of(child));
			console::println("");
		};
	};
};

fn find(path: str) void = {
	if (!fs::exists(path)) {
		console::println("no such path");
		return;
	};
	const root = *(&path: *[]u8);
	seed(root);
	if (isdir(pbuf[0][..plen[0]])) {
		load(0, pbuf[0][..plen[0]]);
		walk_find(0);
	} else {
		console::println(*(&pbuf[0][..plen[0]]: *str));
	};
};

fn walk_find(d: size) void = {
	if (d + 1 >= MAXDEPTH) {
		return;
	};
	const list = lbuf[d][..llen[d]];
	let at = 0z;
	for (let k = 0z; at < len(list); k += 1) {
		let (name, next) = name_at(list, at);
		at = next;
		if (len(name) == 0) {
			continue;
		};
		const n = setpath(d + 1, pbuf[d][..plen[d]], name);
		const child = pbuf[d + 1][..n];
		if (isdir(child)) {
			load(d + 1, child);
			walk_find(d + 1);
		} else {
			console::println(*(&child: *str));
		};
	};
};

fn stat(path: str) void = {
	if (!fs::exists(path)) {
		console::println("no such path");
		return;
	};
	let st = fs::filestat { length = 0, isdir = false };
	_ = fs::stat(path, &st);
	console::print(path);
	if (st.isdir) {
		console::println(": directory");
		return;
	};
	console::print(": ");
	console::printnum(st.length);
	console::println(" bytes");
};

// How much a tree holds, one line per file and then the total.
fn usage_of(path: str) void = {
	if (!fs::exists(path)) {
		console::println("no such path");
		return;
	};
	const root = *(&path: *[]u8);
	seed(root);
	if (!isdir(pbuf[0][..plen[0]])) {
		console::printnum(size_of(pbuf[0][..plen[0]]));
		console::print(" ");
		console::println(path);
		return;
	};
	load(0, pbuf[0][..plen[0]]);
	const total = usage_walk(0);
	console::print("total ");
	console::printnum(total);
	console::println(" bytes");
};

fn usage_walk(d: size) u64 = {
	if (d + 1 >= MAXDEPTH) {
		return 0;
	};
	const list = lbuf[d][..llen[d]];
	let at = 0z;
	let sum: u64 = 0;
	for (let k = 0z; at < len(list); k += 1) {
		let (name, next) = name_at(list, at);
		at = next;
		if (len(name) == 0) {
			continue;
		};
		const n = setpath(d + 1, pbuf[d][..plen[d]], name);
		const child = pbuf[d + 1][..n];
		let bytes: u64 = 0;
		if (isdir(child)) {
			load(d + 1, child);
			bytes = usage_walk(d + 1);
		} else {
			bytes = size_of(child);
		};
		console::printnum(bytes);
		console::putc(' ': u8);
		console::println(*(&child: *str));
		sum += bytes;
	};
	return sum;
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
	console::printnum(sched::live(): u64);
	console::putc('\n');
	for (let i = 0z; i < NWORKERS; i += 1) {
		console::print("worker ");
		console::printnum(i: u64);
		console::print(": ");
		console::printnum(counters[i]);
		console::putc('\n');
	};
};

// What memory the kernel has, and what is left of it.
fn free_mem(mib: u64) void = {
	console::print("frames free ");
	console::printnum(mem::free_frames());
	console::print(" of ");
	console::printnum(mem::total_frames());
	console::println("");
	console::print("available: ");
	console::printnum(mib);
	console::println(" MiB");
};

// How much room the disk has. The format reserves the first sector for its
// superblock and gives every file four sectors, which is the whole of the
// bookkeeping there is.
fn disk_free() void = {
	if (!block::present_drive()) {
		console::println("no drive attached");
		return;
	};
	const total = block::nsect();
	console::print("sectors ");
	console::printnum(total);
	console::print(" (");
	console::printnum(total * 512);
	console::println(" bytes)");
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