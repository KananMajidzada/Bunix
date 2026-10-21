use architecture;
use console;
use fs;
use kit;
use loader;
use rt;
use sched;

export def EXIT: u64 = 0;
export def WRITE: u64 = 1;
export def READFILE: u64 = 2;
export def ALLOC: u64 = 3;
export def WRITEFILE: u64 = 4;
export def READCHR: u64 = 5;
export def YIELD: u64 = 6;
export def CREATE: u64 = 7;
export def REMOVE: u64 = 8;
export def READDIR: u64 = 9;
export def HALT: u64 = 10;
export def SPAWN: u64 = 11;
export def ALIVE: u64 = 12;
export def FRESH: u64 = 13;
export def SPAWN_SHARED: u64 = 14;
export def APPEND: u64 = 15;
export def STAT: u64 = 16;
export def SCREEN: u64 = 17;
export def CHDIR: u64 = 18;
export def PWD: u64 = 19;
export def PS: u64 = 20;
export def KILL: u64 = 21;
export def READAT: u64 = 22;
export def WRITEAT: u64 = 23;
export def REDIRECT: u64 = 24;

type raw = struct {
	data: *[*]u8,
	length: size,
	capacity: size,
};

export fn init() void = {
	architecture::syscall_hook = &handle;
};

fn asstr(ptr: uintptr, n: size) str = {
	let r = raw {
		data = ptr: *[*]u8,
		length = n,
		capacity = n,
	};
	return *(&r: *str);
};

// The bytes a user called read with, viewed as a slice so the filesystem can
// fill them in place. This is what keeps a read from being limited to some
// fixed intermediate buffer.
fn asbuf(ptr: uintptr, n: size) []u8 = {
	let r = raw {
		data = ptr: *[*]u8,
		length = n,
		capacity = n,
	};
	return *(&r: *[]u8);
};

fn readfile(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const dest = asbuf(regs.rdx: uintptr, regs.rcx: size);
	return fs::read(path, dest): u64;
};

fn writefile(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const data = asstr(regs.rdx: uintptr, regs.rcx: size);
	const b = *(&data: *[]u8);
	return fs::write_file(path, b): u64;
};

// Adds to the end of a file, making it when it is not there yet.
fn appendfile(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const data = asstr(regs.rdx: uintptr, regs.rcx: size);
	const b = *(&data: *[]u8);
	return fs::append_file(path, b): u64;
};

// The output of a process goes to the file it was sent to, when it has one,
// and to the screen otherwise. The file is named by the path and the length
// of it, the mode says whether the file is emptied first or added to, and
// the file is made when it is not there yet.
fn redirectpath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const mode = regs.rdx;
	const id = sched::current_id();
	if (len(path) == 0 || mode == 0) {
		// No file: the output goes back to the screen.
		let none: [8]u8 = [0...];
		sched::set_redirect(id, none[..0], 0);
		return 1;
	};
	const p = *(&path: *[]u8);
	if (mode == 1) {
		// The file is emptied first, so that what is written to it is
		// all that is in it.
		let empty: [8]u8 = [0...];
		fs::write_file(path, empty[..0]);
		sched::set_redirect(id, p, 0);
		return 1;
	};
	if (!fs::exists(path)) {
		fs::create(path, false);
	};
	// The output is added to what the file already holds.
	let st = fs::filestat { length = 0, isdir = false };
	let place = 0u64;
	if (fs::stat(path, &st)) {
		place = st.length;
	};
	sched::set_redirect(id, p, place);
	return 1;
};

// The output of a process, which goes to a file when the process has been
// sent one and to the screen otherwise.
fn writeout(regs: *architecture::registers) u64 = {
	const id = sched::current_id();
	const path = sched::redirect_path(id);
	if (len(path) == 0) {
		console::write_raw(regs.rdi: uintptr, regs.rsi: size);
		return regs.rsi: u64;
	};
	const data = asbuf(regs.rdi: uintptr, regs.rsi: size);
	const n = fs::append_at(path, data, sched::redirect_place(id));
	sched::redirect_advance(id, n: u64);
	return n: u64;
};

fn createpath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	return if (fs::create(path, regs.rdx != 0)) 1 else 0;
};

fn removepath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	return if (fs::remove(path)) 1 else 0;
};

// Fills *(u64*)rdx with the size and *(u32*)rcx with 1 for a directory or 0 for
// a file. Returns 1 when the path exists, 0 when it does not.
fn statpath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	let st = fs::filestat { length = 0, isdir = false };
	if (!fs::stat(path, &st)) {
		return 0;
	};
	*((regs.rdx: uintptr): *u64) = st.length;
	*((regs.rcx: uintptr): *u32) = if (st.isdir) 1 else 0;
	return 1;
};

fn readdirpath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const data = fs::list_path(path);
	let n = len(data);
	if (n > (regs.rcx: size)) {
		n = regs.rcx: size;
	};
	for (let i = 0z; i < n; i += 1) {
		const p = ((regs.rdx: uintptr) + (i: uintptr)): *u8;
		*p = data[i];
	};
	return n: u64;
};

fn spawnpath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const id = loader::run_fresh(path): u64;
	inherit_redirect(id);
	return id;
};

// Starts a program in the caller's namespace, so it sees the same files.
fn spawnpath_shared(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const id = loader::run(path): u64;
	inherit_redirect(id);
	return id;
};

// A program started while the output is going to a file sends its output to
// the same file, at the end of what is already in it.
fn inherit_redirect(id: size) void = {
	if (id == sched::NOID) {
		return;
	};
	const path = sched::redirect_path(sched::current_id());
	if (len(path) == 0) {
		return;
	};
	let place = sched::redirect_place(sched::current_id());
	let st = fs::filestat { length = 0, isdir = false };
	if (fs::stat(path, &st)) {
		place = st.length;
	};
	sched::set_redirect(id, *(&path: *[]u8), place);
};

// The processes that are running, one per line: the number of the process
// and the command it was started with.
fn pslist(regs: *architecture::registers) u64 = {
	const n = sched::list(asbuf(regs.rdi: uintptr, regs.rsi: size));
	return n: u64;
};

// Stops a process.
fn killpid(regs: *architecture::registers) u64 = {
	return if (sched::kill(regs.rdi: size)) 1 else 0;
};

// Reads a file from an offset. The offset is in the fifth register, which
// is where the fifth argument of a call goes.
fn readat(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const dest = asbuf(regs.rdx: uintptr, regs.rcx: size);
	return fs::read_at(path, regs.r8: u64, dest): u64;
};

// Writes to a file at an offset.
fn writeat(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const data = asstr(regs.rdx: uintptr, regs.rcx: size);
	const b = *(&data: *[]u8);
	return fs::write_at(path, b, regs.r8: u64): u64;
};

// Moves the calling process into a directory. A relative path is from where
// the process already is.
fn changepath(regs: *architecture::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	return if (fs::chdir(path)) 1 else 0;
};

// Writes the calling process's directory into a buffer it owns. The path is
// made here rather than in the caller, since only the kernel knows which node
// a process is sitting in.
fn cwdpath(regs: *architecture::registers) u64 = {
	const p = fs::cwd();
	const b = *(&p: *[]u8);
	const n = len(b);
	if (n > (regs.rsi: size)) {
		return 0;
	};
	for (let i = 0z; i < n; i += 1) {
		const q = ((regs.rdi: uintptr) + (i: uintptr)): *u8;
		*q = b[i];
	};
	return n: u64;
};

fn handle(regs: *architecture::registers) uintptr = {
	switch (regs.rax) {
	case EXIT =>
		sched::retire();
		return sched::tick(regs);
	case WRITE =>
		regs.rax = writeout(regs);
		return regs: uintptr;
	case READFILE =>
		regs.rax = readfile(regs);
		return regs: uintptr;
	case ALLOC =>
		regs.rax = sched::user_alloc(regs.rdi);
		return regs: uintptr;
	case WRITEFILE =>
		regs.rax = writefile(regs);
		return regs: uintptr;
	case APPEND =>
		regs.rax = appendfile(regs);
		return regs: uintptr;
	case REDIRECT =>
		regs.rax = redirectpath(regs);
		return regs: uintptr;
	case READCHR =>
		// A keystroke goes to the shell behind the window that has the
		// focus, so typing into a new terminal is not swallowed by a
		// program still running in another one.
		regs.rax = sched::deliver(console::pollch()): u64;
		return regs: uintptr;
	case YIELD =>
		console::poll_mouse();
		regs.rax = 0;
		return sched::tick(regs);
	case CREATE =>
		regs.rax = createpath(regs);
		return regs: uintptr;
	case REMOVE =>
		regs.rax = removepath(regs);
		return regs: uintptr;
	case READDIR =>
		regs.rax = readdirpath(regs);
		return regs: uintptr;
	case STAT =>
		regs.rax = statpath(regs);
		return regs: uintptr;
	case SCREEN =>
		// The console size, so a program can fit itself to the screen.
		*((regs.rdi: uintptr): *u32) = console::screen_rows(): u32;
		*((regs.rsi: uintptr): *u32) = console::screen_cols(): u32;
		regs.rax = 1;
		return regs: uintptr;
	case HALT =>
		rt::halt();
	case SPAWN =>
		regs.rax = spawnpath(regs);
		return regs: uintptr;
	case SPAWN_SHARED =>
		regs.rax = spawnpath_shared(regs);
		return regs: uintptr;
	case ALIVE =>
		regs.rax = if (sched::alive(regs.rdi: size)) 1 else 0;
		return regs: uintptr;
	case FRESH =>
		regs.rax = if (kit::take_fresh()) 1 else 0;
		return regs: uintptr;
	case CHDIR =>
		regs.rax = changepath(regs);
		return regs: uintptr;
	case PWD =>
		regs.rax = cwdpath(regs);
		return regs: uintptr;
	case PS =>
		regs.rax = pslist(regs);
		return regs: uintptr;
	case KILL =>
		regs.rax = killpid(regs);
		return regs: uintptr;
	case READAT =>
		regs.rax = readat(regs);
		return regs: uintptr;
	case WRITEAT =>
		regs.rax = writeat(regs);
		return regs: uintptr;
	case =>
		regs.rax = 0xFFFFFFFFFFFFFFFF;
		return regs: uintptr;
	};
};
