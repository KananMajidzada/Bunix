use fs;
use mem;
use paging;
use sched;
use user;

export const BASE: u64 = 0x400000;
// The window above the image: the heap grows up from the end of the program,
// then the argument page, then the stack at the top. A program that draws
// keeps a whole screen of pixels and a game's working set besides, so the
// window is the 32 MiB that paging lays out for every space: 0x400000 to
// 0x2400000, with the argument page at 0x23E0000 a good way below the stack
// so a deep recursion runs into the guard long before it reaches the
// arguments.
export const WINDOW: u64 = 0x2000000;
export const STACK_TOP: u64 = 0x2400000;
export const ARG: u64 = 0x23E0000;
export const HEAP_END: u64 = 0x23E0000;

def PAGE: u64 = 4096;
// The stack has to hold whatever the program recurses with, and a compiler
// recurses a long way down its own syntax tree.
def STACK_PAGES: u64 = 16;
def MAXARG: size = 4096;

type hdr = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

fn roundup(n: u64) u64 = (n + PAGE - 1) & ~(PAGE - 1);

fn slice_of(addr: uintptr, n: size) []u8 = {
	const h = hdr { data = addr, length = n, capacity = n };
	return *(&h: *[]u8);
};

export fn reserve() void = {
	mem::reserve(BASE: uintptr, WINDOW);
};

export fn run(arg: str) size = run_with(arg, false);

// Starts a process with a fresh namespace of its own.
export fn run_fresh(arg: str) size = run_with(arg, true);

// The first word of the argument names the program. A path is stripped down to
// its last element, so /bin/wc and wc select the same image.
fn pick(b: []u8) int = {
	let e = 0z;
	for (e < len(b) && b[e] != (' ': u8)) {
		e += 1;
	};
	let s = 0z;
	for (let i = 0z; i < e; i += 1) {
		if (b[i] == ('/': u8)) {
			s = i + 1;
		};
	};
	const word = b[s..e];
	for (let i = 0z; i < len(user::programs); i += 1) {
		const nm = *(&user::programs[i].nam: *[]u8);
		if (same(nm, word)) {
			return i: int;
		};
	};
	return -1;
};

fn same(a: []u8, b: []u8) bool = {
	if (len(a) != len(b)) {
		return false;
	};
	for (let i = 0z; i < len(a); i += 1) {
		if (a[i] != b[i]) {
			return false;
		};
	};
	return true;
};

// The argument left after the program name, skipping one space.
fn rest_of(b: []u8) []u8 = {
	let e = 0z;
	for (e < len(b) && b[e] != (' ': u8)) {
		e += 1;
	};
	if (e < len(b)) {
		e += 1;
	};
	return b[e..];
};

// The first word of the line: the program being asked for.
fn first_word(b: []u8) []u8 = {
	let e = 0z;
	for (e < len(b) && b[e] != (' ': u8)) {
		e += 1;
	};
	return b[..e];
};

// Everything a new process needs above its image: a stack at the top of the
// window and one page holding the argument string.
fn finish(
	space: uintptr,
	entry: u64,
	image_end: u64,
	payload: []u8,
	fresh: bool,
	cmd: []u8,
) size = {
	// One byte of the argument page is left for the terminator the C runtime
	// puts at the end of the last argument, so a payload filling the page
	// exactly would have nowhere to put it.
	if (len(payload) >= MAXARG) {
		return sched::NOID;
	};
	for (let i = 0u64; i < STACK_PAGES; i += 1) {
		const frame = mem::frames_alloc(1);
		if (frame == 0) {
			return sched::NOID;
		};
		paging::map_user(space, STACK_TOP - (i + 1) * PAGE, frame, true);
	};
	const aframe = mem::frames_alloc(1);
	if (aframe == 0) {
		return sched::NOID;
	};
	paging::map_user(space, ARG, aframe, true);
	for (let i = 0z; i < len(payload); i += 1) {
		*((aframe + (i: uintptr)): *u8) = payload[i];
	};
	// The C runtime splits this string in place and terminates each argument
	// as it goes, which needs a byte at the very end that the payload itself
	// does not hold.
	*((aframe + (len(payload): uintptr)): *u8) = 0;
	const id = sched::spawn_user(
		entry: uintptr,
		STACK_TOP: uintptr,
		ARG: uintptr,
		len(payload),
		space,
		image_end: uintptr,
		HEAP_END: uintptr,
	);
	if (id != sched::NOID) {
		fs::ns_install(id, fresh);
		sched::set_cmd(id, cmd);
	};
	return id;
};

def PTLOAD: u32 = 1;
def ELFCLASS64: u8 = 2;
def ETEXEC: u16 = 2;
def ETDYN: u16 = 3;
def PHENT: u64 = 56;
def MAXPH: u16 = 64;

// Cheap check for "is this an executable image", so the shell can tell a file
// to run from a name that is simply wrong.
fn looks_executable(path: []u8) bool = {
	let st = fs::filestat { length = 0, isdir = false };
	if (!fs::stat(*(&path: *str), &st) || st.isdir || st.length < 64) {
		return false;
	};
	let head: [4]u8 = [0...];
	const n = fs::read(*(&path: *str), head[..]);
	return n == 4 && head[0] == 0x7f && head[1] == ('E': u8) &&
		head[2] == ('L': u8) && head[3] == ('F': u8);
};

// Runs an executable that lives in the filesystem: the ELF a compiler has just
// written, as opposed to one of the images folded into the kernel. The file is
// a flat x86-64 image linked at BASE, so it is mapped segment by segment out of
// its own program headers.
fn run_elf(path: []u8, payload: []u8) size = {
	let st = fs::filestat { length = 0, isdir = false };
	if (!fs::stat(*(&path: *str), &st) || st.isdir || st.length < 64) {
		return sched::NOID;
	};
	const bytes = mem::frames_alloc(roundup(st.length) / PAGE);
	if (bytes == 0) {
		return sched::NOID;
	};
	const got = fs::read(*(&path: *str), slice_of(bytes, st.length: size));
	if (got < 64) {
		mem::release(bytes);
		return sched::NOID;
	};
	if (*((bytes + 4: uintptr): *u8) != ELFCLASS64) {
		mem::release(bytes);
		return sched::NOID;
	};
	const etype = *((bytes + 16: uintptr): *u16);
	if (etype != ETEXEC && etype != ETDYN) {
		mem::release(bytes);
		return sched::NOID;
	};
	const entry = *((bytes + 24: uintptr): *u64);
	const phoff = *((bytes + 32: uintptr): *u64);
	const phnum = *((bytes + 56: uintptr): *u16);
	const phent = *((bytes + 54: uintptr): *u16);
	if (phent: u64 < PHENT || phnum == 0 || phnum > MAXPH) {
		mem::release(bytes);
		return sched::NOID;
	};
	if (phoff + phnum: u64 * phent: u64 > st.length) {
		mem::release(bytes);
		return sched::NOID;
	};

	// Where the image lands: the span its loadable segments cover.
	let lo = ~0u64;
	let hi = 0u64;
	for (let i = 0u16; i < phnum; i += 1) {
		const ph = bytes + (phoff + (i: u64) * phent: u64): uintptr;
		if (*((ph): *u32) != PTLOAD) {
			continue;
		};
		const start = *((ph + 16: uintptr): *u64) & ~(PAGE - 1);
		const end = roundup(*((ph + 16: uintptr): *u64) + *((ph + 40: uintptr): *u64));
		if (start < lo) {
			lo = start;
		};
		if (end > hi) {
			hi = end;
		};
	};
	if (lo >= hi || lo < BASE || hi >= HEAP_END) {
		mem::release(bytes);
		return sched::NOID;
	};

	const span = hi - lo;
	const frames = mem::frames_alloc(span / PAGE);
	if (frames == 0) {
		mem::release(bytes);
		return sched::NOID;
	};
	const space = paging::space_new();
	if (space == 0) {
		mem::release(frames);
		mem::release(bytes);
		return sched::NOID;
	};
	for (let i = 0u64; i < span / PAGE; i += 1) {
		paging::map_user(space, lo + i * PAGE, frames + (i * PAGE): uintptr, true);
	};
	// Freshly allocated frames are not zeroed, and the gap between a segment's
	// file bytes and its memory size has to read back as zeroes.
	for (let i = 0u64; i < span; i += 1) {
		*((frames + (i: uintptr)): *u8) = 0;
	};
	for (let i = 0u16; i < phnum; i += 1) {
		const ph = bytes + (phoff + (i: u64) * phent: u64): uintptr;
		if (*((ph): *u32) != PTLOAD) {
			continue;
		};
		const poff = *((ph + 8: uintptr): *u64);
		const vaddr = *((ph + 16: uintptr): *u64);
		const filesz = *((ph + 32: uintptr): *u64);
		if (vaddr < lo || vaddr > hi) {
			continue;
		};
		const dst = frames + (vaddr - lo): uintptr;
		const room = hi - vaddr;
		let n = filesz;
		if (n > room) {
			n = room;
		};
		if (poff + n > st.length) {
			n = if (poff < st.length) st.length - poff else 0;
		};
		for (let j = 0u64; j < n; j += 1) {
			*((dst + (j: uintptr)): *u8) = *((bytes + ((poff + j): uintptr)): *u8);
		};
	};
	mem::release(bytes);
	return finish(space, entry, hi, payload, false, path);
};

fn run_with(arg: str, fresh: bool) size = {
	const b = *(&arg: *[]u8);

	// A word naming an executable in the filesystem runs that, which is how a
	// program a compiler just produced gets to run. The path has to be
	// checked before the built-in names: pick() matches on the last element, so
	// without this /tmp/hello would find the image folded in as /bin/hello.
	const word = first_word(b);
	if (len(word) > 0 && word[0] == ('/': u8) && looks_executable(word)) {
		return run_elf(word, rest_of(b));
	};

	// Otherwise a name matching one of the images folded into the kernel runs
	// that, and anything else falls back to the shell image, which is how the
	// shell itself starts and how a plain file still gets read out.
	const pi = pick(b);

	let blob = slice_of(&user::prog[0]: uintptr, len(user::prog));
	let image_end = user::image_end;
	let entry = user::entry;
	let payload = b;
	if (pi >= 0) {
		const p = &user::programs[pi];
		const pool = (&user::blobs): uintptr;
		blob = slice_of(pool + p.off, p.bytes);
		image_end = p.end;
		entry = p.entry;
		payload = rest_of(b);
	};
	if (len(payload) > MAXARG) {
		return sched::NOID;
	};

	const space = paging::space_new();
	if (space == 0) {
		return sched::NOID;
	};

	const image_bytes = roundup(image_end) - BASE;
	const image_pages = image_bytes / PAGE;
	const frames = mem::frames_alloc(image_pages);
	if (frames == 0) {
		return sched::NOID;
	};
	for (let i = 0u64; i < image_pages; i += 1) {
		paging::map_user(space, BASE + i * PAGE, frames + (i * PAGE): uintptr, true);
	};
	for (let i = 0z; i < len(blob); i += 1) {
		*((frames + (i: uintptr)): *u8) = blob[i];
	};
	for (let i = len(blob); i < image_bytes: size; i += 1) {
		*((frames + (i: uintptr)): *u8) = 0;
	};

	return finish(space, entry, BASE + image_bytes, payload, fresh, b);
};
