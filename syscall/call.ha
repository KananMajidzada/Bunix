use arch;
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
export def HALT: u64 = 9;
export def SPAWN: u64 = 10;
export def ALIVE: u64 = 11;
export def FRESH: u64 = 12;

type raw = struct {
	data: *[*]u8,
	length: size,
	capacity: size,
};

export fn init() void = {
	arch::syscall_hook = &handle;
};

fn asstr(ptr: uintptr, n: size) str = {
	let r = raw {
		data = ptr: *[*]u8,
		length = n,
		capacity = n,
	};
	return *(&r: *str);
};

fn readfile(regs: *arch::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const data = fs::cat(path);
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

fn writefile(regs: *arch::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	const data = asstr(regs.rdx: uintptr, regs.rcx: size);
	const b = *(&data: *[]u8);
	return fs::write_file(path, b): u64;
};

fn createpath(regs: *arch::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	return if (fs::create(path, regs.rdx != 0)) 1 else 0;
};

fn removepath(regs: *arch::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	return if (fs::remove(path)) 1 else 0;
};

fn spawnpath(regs: *arch::registers) u64 = {
	const path = asstr(regs.rdi: uintptr, regs.rsi: size);
	return loader::run_fresh(path): u64;
};

fn handle(regs: *arch::registers) uintptr = {
	switch (regs.rax) {
	case EXIT =>
		sched::retire();
		return sched::tick(regs);
	case WRITE =>
		console::write_raw(regs.rdi: uintptr, regs.rsi: size);
		regs.rax = regs.rsi;
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
	case READCHR =>
		regs.rax = console::pollch(): u64;
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
	case HALT =>
		rt::halt();
	case SPAWN =>
		regs.rax = spawnpath(regs);
		return regs: uintptr;
	case ALIVE =>
		regs.rax = if (sched::alive(regs.rdi: size)) 1 else 0;
		return regs: uintptr;
	case FRESH =>
		regs.rax = if (kit::take_fresh()) 1 else 0;
		return regs: uintptr;
	case =>
		regs.rax = 0xFFFFFFFFFFFFFFFF;
		return regs: uintptr;
	};
};
