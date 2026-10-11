use arch;
use mem;
use paging;

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
	space: uintptr,
	heap: uintptr,
	heap_end: uintptr,
	alive: bool,
};

let threads: [MAXTHREADS]thread = [thread {
	id = 0, stack = 0, kernel = 0, frame = 0,
	space = 0, heap = 0, heap_end = 0, alive = false,
}...];
let nthreads: size = 0;
let current: size = 0;

// Called when a thread dies, so modules can drop its per-process state.
export let reap_hook: nullable *fn(id: size) void = null;

fn call_reap() void = {
	match (reap_hook) {
	case null => void;
	case let f: *fn(id: size) void =>
		f(threads[current].id: size);
	};
};

export fn start() void = {
	threads[0] = thread {
		id = 0, stack = 0, kernel = 0, frame = 0,
		space = 0, heap = 0, heap_end = 0, alive = true,
	};
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
	call_reap();
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

fn enter(id: size, stack: uintptr, fp: uintptr, space: uintptr) void = {
	threads[id] = thread {
		id = id: u64,
		stack = stack,
		kernel = stack + ((STACK_PAGES * 4096): uintptr),
		frame = fp,
		space = space,
		heap = 0,
		heap_end = 0,
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
	enter(id, stack, fp, 0);
	return true;
};

export fn spawn_user(
	entry: uintptr,
	ustack: uintptr,
	argptr: uintptr,
	arglen: size,
	space: uintptr,
	heap: uintptr,
	heap_end: uintptr,
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
	enter(id, stack, fp, space);
	threads[id].heap = heap;
	threads[id].heap_end = heap_end;
	return id;
};

// Hands out user memory for the running process, mapping fresh frames into its
// window and returning the user virtual address.
export fn user_alloc(pages: u64) uintptr = {
	const t = &threads[current];
	if (t.space == 0 || pages == 0) {
		return 0;
	};
	const bytes = (pages * 4096): uintptr;
	if (t.heap + bytes > t.heap_end) {
		return 0;
	};
	const base = t.heap;
	for (let i = 0u64; i < pages; i += 1) {
		const frame = mem::frames_alloc(1);
		if (frame == 0) {
			return 0;
		};
		const va = t.heap + (i * 4096): uintptr;
		paging::map_user(t.space, va: u64, frame, true);
		paging::flush(va: u64);
	};
	t.heap += bytes;
	return base;
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
	const sp = threads[current].space;
	const target = if (sp == 0) paging::kernel() else sp;
	if (target != paging::current()) {
		paging::leave(target);
	};
	return threads[current].frame;
};

export fn tick(regs: *arch::registers) uintptr = {
	threads[current].frame = regs: uintptr;
	return pick_next();
};

// Terminates the running thread after a fault and returns the next frame.
export fn fault_kill() uintptr = {
	threads[current].alive = false;
	call_reap();
	return pick_next();
};
