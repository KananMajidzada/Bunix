use arch;
use mem;

def MAXTHREADS: size = 8;
def STACK_PAGES: u64 = 4;
def FRAME: uintptr = 176;

export def NOID: size = ~0z;

const RING3_CODE: u64 = 0x1B;
const RING3_DATA: u64 = 0x23;

export type thread = struct {
	id: u64,
	stack: uintptr,
	kernel: uintptr,
	frame: uintptr,
	alive: bool,
};

let threads: [MAXTHREADS]thread = [thread {
	id = 0, stack = 0, kernel = 0, frame = 0, alive = false,
}...];
let nthreads: size = 0;
let current: size = 0;

export fn start() void = {
	threads[0] = thread { id = 0, stack = 0, kernel = 0, frame = 0, alive = true };
	nthreads = 1;
	current = 0;
};

export fn count() size = nthreads;

export fn live() size = {
	let n = 0z;
	for (let i = 0z; i < nthreads; i += 1) {
		if (threads[i].alive) {
			n += 1;
		};
	};
	return n;
};

export fn running() u64 = threads[current].id;

export fn alive(id: size) bool = id < nthreads && threads[id].alive;

export fn retire() void = {
	threads[current].alive = false;
};

fn put(fp: uintptr, off: uintptr, v: u64) void = {
	const p = (fp + off): *u64;
	*p = v;
};

fn blank(fp: uintptr) void = {
	for (let i = 0u64; i < FRAME: u64; i += 1) {
		const p = (fp + (i: uintptr)): *u8;
		*p = 0;
	};
};

fn free_slot() size = {
	for (let i = 1z; i < nthreads; i += 1) {
		if (!threads[i].alive) {
			return i;
		};
	};
	if (nthreads < MAXTHREADS) {
		const id = nthreads;
		nthreads += 1;
		return id;
	};
	return NOID;
};

fn enter(id: size, stack: uintptr, fp: uintptr) void = {
	threads[id] = thread {
		id = id: u64,
		stack = stack,
		kernel = stack + ((STACK_PAGES * 4096): uintptr),
		frame = fp,
		alive = true,
	};
};

export fn spawn(entry: *fn(arg: uintptr) void, arg: uintptr) bool = {
	const id = free_slot();
	if (id == NOID) {
		return false;
	};
	const stack = mem::frames_alloc(STACK_PAGES);
	if (stack == 0) {
		return false;
	};
	const top = stack + ((STACK_PAGES * 4096): uintptr);
	const fp = top - FRAME;
	blank(fp);
	put(fp, 72, arg: u64);
	put(fp, 136, (entry: uintptr): u64);
	put(fp, 144, 0x08);
	put(fp, 152, 0x202);
	put(fp, 160, (top - 8): u64);
	put(fp, 168, 0x10);
	enter(id, stack, fp);
	return true;
};

export fn spawn_user(
	entry: uintptr,
	ustack: uintptr,
	argptr: uintptr,
	arglen: size,
) size = {
	const id = free_slot();
	if (id == NOID) {
		return NOID;
	};
	const stack = mem::frames_alloc(STACK_PAGES);
	if (stack == 0) {
		return NOID;
	};
	const top = stack + ((STACK_PAGES * 4096): uintptr);
	const fp = top - FRAME;
	blank(fp);
	put(fp, 72, argptr: u64);
	put(fp, 80, arglen: u64);
	put(fp, 136, entry);
	put(fp, 144, RING3_CODE);
	put(fp, 152, 0x202);
	put(fp, 160, ustack);
	put(fp, 168, RING3_DATA);
	enter(id, stack, fp);
	return id;
};

fn pick_next() uintptr = {
	for (let i = 1z; i <= nthreads; i += 1) {
		const j = (current + i) % nthreads;
		if (threads[j].alive) {
			current = j;
			break;
		};
	};
	if (threads[current].kernel != 0) {
		arch::set_rsp0(threads[current].kernel);
	};
	return threads[current].frame;
};

export fn tick(regs: *arch::registers) uintptr = {
	threads[current].frame = regs: uintptr;
	return pick_next();
};
