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

fn roundup(n: u64) u64 = (n + PAGE - 1) & ~(PAGE - 1);

export fn reserve() void = {
	mem::reserve(BASE: uintptr, 0x400000);
};

export fn run(path: str) size = run_with(path, false);

// Starts a process with a fresh namespace of its own.
export fn run_fresh(path: str) size = run_with(path, true);

fn run_with(path: str, fresh: bool) size = {
	const space = paging::space_new();
	if (space == 0) {
		return sched::NOID;
	};

	const image_end = roundup(user::image_end);
	const image_bytes = image_end - BASE;
	const image_pages = image_bytes / PAGE;
	const frames = mem::frames_alloc(image_pages);
	if (frames == 0) {
		return sched::NOID;
	};
	for (let i = 0u64; i < image_pages; i += 1) {
		paging::map_user(space, BASE + i * PAGE, frames + (i * PAGE): uintptr, true);
	};
	const total = image_bytes: size;
	for (let i = 0z; i < len(user::prog); i += 1) {
		*((frames + (i: uintptr)): *u8) = user::prog[i];
	};
	for (let i = len(user::prog); i < total; i += 1) {
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
	const b = *(&path: *[]u8);
	if (len(b) > 4096) {
		return sched::NOID;
	};
	for (let i = 0z; i < len(b); i += 1) {
		*((aframe + (i: uintptr)): *u8) = b[i];
	};

	const id = sched::spawn_user(
		user::entry: uintptr,
		STACK_TOP: uintptr,
		ARG: uintptr,
		len(b),
		space,
		image_end: uintptr,
		HEAP_END: uintptr,
	);
	if (id != sched::NOID) {
		fs::ns_install(id, fresh);
	};
	return id;
};
