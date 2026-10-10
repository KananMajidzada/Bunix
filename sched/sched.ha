use arch;
use mem;

def MAXTHREADS: size = 8;
def STACK_PAGES: u64 = 4;
def FRAME: uintptr = 176;

export type thread = struct {
	id: u64,
	stack: uintptr,
	frame: uintptr,
	alive: bool,
};

let threads: [MAXTHREADS]thread = [thread {
	id = 0, stack = 0, frame = 0, alive = false,
}...];
let nthreads: size = 0;
let current: size = 0;

export fn start() void = {
	threads[0] = thread { id = 0, stack = 0, frame = 0, alive = true };
	nthreads = 1;
	current = 0;
};

export fn count() size = nthreads;

export fn running() u64 = threads[current].id;

fn put(fp: uintptr, off: uintptr, v: u64) void = {
	const p = (fp + off): *u64;
	*p = v;
};

fn frame_for(entry: *fn(arg: uintptr) void, arg: uintptr, top: uintptr) uintptr = {
	const fp = top - FRAME;
	for (let i = 0u64; i < FRAME: u64; i += 1) {
		const p = (fp + (i: uintptr)): *u8;
		*p = 0;
	};
	put(fp, 72, arg: u64);
	put(fp, 136, (entry: uintptr): u64);
	put(fp, 144, 0x08);
	put(fp, 152, 0x202);
	put(fp, 160, (top - 8): u64);
	put(fp, 168, 0x10);
	return fp;
};

export fn spawn(entry: *fn(arg: uintptr) void, arg: uintptr) bool = {
	if (nthreads >= MAXTHREADS) {
		return false;
	};
	const stack = mem::frames_alloc(STACK_PAGES);
	if (stack == 0) {
		return false;
	};
	const top = stack + ((STACK_PAGES * 4096): uintptr);
	const id = nthreads;
	threads[id] = thread {
		id = id: u64,
		stack = stack,
		frame = frame_for(entry, arg, top),
		alive = true,
	};
	nthreads += 1;
	return true;
};

export fn tick(regs: *arch::registers) uintptr = {
	threads[current].frame = regs: uintptr;
	for (let i = 1z; i <= nthreads; i += 1) {
		const j = (current + i) % nthreads;
		if (threads[j].alive) {
			current = j;
			break;
		};
	};
	return threads[current].frame;
};
