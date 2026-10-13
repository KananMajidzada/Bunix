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
	fpu: uintptr,
	alive: bool,
};

// Where the FPU and SSE state of each thread is parked across a switch. The
// x86-64 syscall convention returns doubles in the SSE registers, so a ported
// compiler needs them across every switch.
def FPU_SZ: size = 512;
let fpuareas: [MAXTHREADS][FPU_SZ]u8 = [[0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...]];
let fpuready: [MAXTHREADS]bool = [false...];

// Turns on the FPU and SSE for the whole machine and gives this thread a clean
// set of registers. CR0.EM must be clear or SSE raises #UD, CR0.TS must be
// clear or every x87 instruction raises #NM, and CR4 has to say that the OS
// handles SSE and the legacy area.
export fn fpu_init() void = {
	const c0 = arch::read_cr0();
	arch::write_cr0((c0 & ~((1 << 2) | (1 << 3))): uintptr);
	const c4 = arch::read_cr4();
	arch::write_cr4((c4 | (1 << 9) | (1 << 10)): uintptr);

	arch::fpu_init(thread_fpu(0));
	fpuready[0] = true;
};

fn thread_fpu(i: size) uintptr = {
	// fxsave wants 16-byte alignment; the array gives us more than that.
	return &fpuareas[i][0]: uintptr;
};

let threads: [MAXTHREADS]thread = [thread {
	id = 0, stack = 0, kernel = 0, frame = 0,
	space = 0, heap = 0, heap_end = 0, fpu = 0, alive = false,
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

// Returns a dead user thread's kernel stack, heap, address space, and all
// frames mapped into it. Kernel threads (space == 0) are left alone.
fn free_user(id: size) void = {
	const t = &threads[id];
	if (t.space == 0) {
		return;
	};
	for (let i = 0u64; i < STACK_PAGES; i += 1) {
		mem::release(t.stack + (i * 4096): uintptr);
	};
	paging::space_free(t.space);
	t.stack = 0;
	t.space = 0;
	t.heap = 0;
	t.heap_end = 0;
};

export fn start() void = {
	threads[0] = thread {
		id = 0, stack = 0, kernel = 0, frame = 0,
		space = 0, heap = 0, heap_end = 0,
		fpu = thread_fpu(0), alive = true,
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
	free_user(current);
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
	// A thread that has never run has no registers worth keeping, so it gets
	// a cleared area rather than whatever the last user of the slot left.
	const save = thread_fpu(id);
	for (let i = 0z; i < FPU_SZ; i += 1) {
		*((save + (i: uintptr)): *u8) = 0;
	};
	arch::fpu_init(save);
	threads[id] = thread {
		id = id: u64,
		stack = stack,
		kernel = stack + ((STACK_PAGES * 4096): uintptr),
		frame = fp,
		space = space,
		heap = 0,
		heap_end = 0,
		fpu = save,
		alive = true,
	};
	fpuready[id] = true;
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
	// Park the outgoing thread's FPU and SSE registers before touching the
	// incoming one's, so the two never share an area.
	if (fpuready[current]) {
		arch::fpu_save(threads[current].fpu);
	};
	let next = current;
	for (let i = 1z; i <= nthreads; i += 1) {
		const j = (current + i) % nthreads;
		if (threads[j].alive) {
			next = j;
			break;
		};
	};
	current = next;
	if (fpuready[current]) {
		arch::fpu_load(threads[current].fpu);
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
	free_user(current);
	call_reap();
	return pick_next();
};
