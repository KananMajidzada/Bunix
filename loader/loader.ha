use fs;
use mem;
use paging;
use sched;
use user;

export const BASE: u64 = 0x400000;
export const STACK_TOP: u64 = 0x600000;
export const ARG: u64 = 0x5E0000;
export const HEAP_END: u64 = 0x5E0000;

def PAGE: u64 = 4096;
def STACK_PAGES: u64 = 4;
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
	mem::reserve(BASE: uintptr, 0x400000);
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

fn run_with(arg: str, fresh: bool) size = {
	const b = *(&arg: *[]u8);

	// Fall back to the shell image; a named program replaces it. The shell
	// sees the whole line, a named program only its arguments.
	let blob = slice_of(&user::prog[0]: uintptr, len(user::prog));
	let image_end = user::image_end;
	let payload = b;
	const pi = pick(b);
	if (pi >= 0) {
		const p = &user::programs[pi];
		const pool = (&user::blobs): uintptr;
		blob = slice_of(pool + p.off, p.bytes);
		image_end = p.end;
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

	const id = sched::spawn_user(
		user::entry: uintptr,
		STACK_TOP: uintptr,
		ARG: uintptr,
		len(payload),
		space,
		(BASE + image_bytes): uintptr,
		HEAP_END: uintptr,
	);
	if (id != sched::NOID) {
		fs::ns_install(id, fresh);
	};
	return id;
};
