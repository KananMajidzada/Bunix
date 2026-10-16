use arch;
use kit;
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
	// The terminal window this thread's output belongs to. A thread keeps to
	// the window it was started in, so a program left running in one window
	// does not paint over another one that is merely being looked at.
	win: size,
	alive: bool,
};

// Where the FPU and SSE state of each thread is parked across a switch. The
// x86-64 syscall convention returns doubles in the SSE registers, so a ported
// compiler needs them across every switch.
//
// fxsave refuses a buffer that is not aligned, raising a general protection
// fault with no faulting address. Where an array lands in .bss depends on
// whatever else happens to be there, so the address cannot be relied on to be
// aligned and is rounded up instead. The state is 512 bytes and the worst
// rounding gives up 63, hence the roomier slot.
def FPU_SZ: size = 1024;
def FPU_ALIGN: uintptr = 64;
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
	const raw = &fpuareas[i][0]: uintptr;
	return (raw + (FPU_ALIGN - 1)) & ~(FPU_ALIGN - 1);
};

let threads: [MAXTHREADS]thread = [thread {
	id = 0, stack = 0, kernel = 0, frame = 0,
	space = 0, heap = 0, heap_end = 0, fpu = 0, win = 0, alive = false,
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
		fpu = thread_fpu(0), win = 0, alive = true,
	};
	nthreads = 1;
	current = 0;
};

// Points a thread that has just been created at a particular window, for a
// shell started to serve a newly opened terminal.
export fn bind_win(id: size, wi: size) void = {
	if (id == NOID || id >= MAXTHREADS) {
		return;
	};
	// The thread was entered in the window of whoever started it, which is
	// not the window it is being sent to. Leaving the foreground record
	// pointing at it would make that window hand its keystrokes to a
	// process belonging to another one.
	const old = threads[id].win;
	threads[id].win = wi;
	if (old < MAXWIN && win_fg[old] == id) {
		win_fg[old] = MAXWIN;
	};
	if (wi < MAXWIN) {
		win_fg[wi] = id;
	};
};

// Keystrokes waiting for each thread. Every terminal window has a shell of its
// own, and they all read the same keyboard, so a byte has to be filed against
// the thread that is meant to receive it rather than handed to whichever one the
// scheduler happens to be running.
def INQ: size = 64;
let inq: [MAXTHREADS * INQ]u8 = [0...];
let inhead: [MAXTHREADS]size = [0...];
let intail: [MAXTHREADS]size = [0...];
let incount: [MAXTHREADS]size = [0...];

// The thread a window is showing: the one most recently started in it and still
// running. A shell and the program it started share a window, and the program
// is the one that must read the keyboard, exactly as a terminal hands input to
// the foreground job rather than to the shell behind it. NONE means the window
// has no job of its own, and the shell behind it takes the input.
def MAXWIN: size = 6;
let win_fg: [MAXWIN]size = [MAXWIN...];

// The shell behind each window. A window's foreground job may come and go, and
// when it does the keystrokes have to go back to the shell that owns the
// window rather than to whichever thread happens to come first: the kernel's
// own first process is a monitor that never reads the keyboard, and it is the
// first live thread in the window the boot shell runs in.
let win_shell: [MAXWIN]size = [MAXWIN...];

// The window the next thread started belongs to. MAXWIN means "the window of
// whoever is starting it", which is right for a program a shell runs.
let spawn_win: size = MAXWIN;

// Names the window a process about to be started should belong to.
export fn set_spawn_win(wi: size) void = {
	spawn_win = wi;
};

fn input_thread() size = {
	const wi = kit::focus_win();
	if (wi < MAXWIN) {
		const fg = win_fg[wi];
		if (fg != MAXWIN && fg < MAXTHREADS && threads[fg].alive
				&& threads[fg].win == wi) {
			return fg;
		};
		const sh = win_shell[wi];
		if (sh != MAXWIN && sh < MAXTHREADS && threads[sh].alive
				&& threads[sh].win == wi) {
			return sh;
		};
		for (let i = 0z; i < nthreads; i += 1) {
			if (threads[i].alive && threads[i].win == wi) {
				return i;
			};
		};
	};
	return current;
};

// Records which shell owns a window, so a window with nothing running in it
// still has somewhere to put keystrokes.
export fn bind_shell(id: size, wi: size) void = {
	if (wi < MAXWIN && id != NOID && id < MAXTHREADS) {
		win_shell[wi] = id;
	};
};

fn push_input(t: size, b: u8) void = {
	if (t >= MAXTHREADS || incount[t] == INQ) {
		return;
	};
	inq[t * INQ + intail[t]] = b;
	intail[t] = (intail[t] + 1) % INQ;
	incount[t] += 1;
};

fn pop_input() u8 = {
	if (incount[current] == 0) {
		return 0;
	};
	const b = inq[current * INQ + inhead[current]];
	inhead[current] = (inhead[current] + 1) % INQ;
	incount[current] -= 1;
	return b;
};

// Files a byte just read from the keyboard against the focused window's thread
// and returns whatever is waiting for the caller.
export fn deliver(b: u8) u8 = {
	if (b != 0) {
		push_input(input_thread(), b);
	};
	return pop_input();
};

// Drops anything a thread had not read before its slot was reused.
fn clear_input(t: size) void = {
	inhead[t] = 0;
	intail[t] = 0;
	incount[t] = 0;
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
	const wi = threads[current].win;
	threads[current].alive = false;
	if (wi < MAXWIN && win_fg[wi] == current) {
		win_fg[wi] = MAXWIN;
	};
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
	clear_input(id);
	const save = thread_fpu(id);
	for (let i = 0z; i < FPU_SZ; i += 1) {
		*((save + (i: uintptr)): *u8) = 0;
	};
	arch::fpu_init(save);
	// A thread started on behalf of a particular terminal belongs to that
	// terminal, not to the window of whichever process happened to ask for
	// it. Setting this before starting the process matters: the very first
	// thing a new shell prints is its banner, and it must not land in the
	// window it was opened over.
	const w = if (spawn_win < MAXWIN) spawn_win else threads[current].win;
	threads[id] = thread {
		id = id: u64,
		stack = stack,
		kernel = stack + ((STACK_PAGES * 4096): uintptr),
		frame = fp,
		space = space,
		heap = 0,
		heap_end = 0,
		fpu = save,
		win = w,
		alive = true,
	};
	if (w < MAXWIN) {
		win_fg[w] = id;
	};
	spawn_win = MAXWIN;
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
	// Output follows the running thread into its own window.
	kit::set_out_win(threads[current].win);
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
