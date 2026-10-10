use mem;
use sched;
use user;

export const BASE: uintptr = 0x400000;
export const SIZE: u64 = 0x400000;
export const STACK: uintptr = 0x7FF000;
export const ARG: uintptr = 0x7F0000;

export fn reserve() void = {
	mem::reserve(BASE, SIZE);
};

export fn run(path: str) size = {
	for (let i = 0z; i < len(user::prog); i += 1) {
		const p = (BASE + (i: uintptr)): *u8;
		*p = user::prog[i];
	};

	const b = *(&path: *[]u8);
	if (len(b) > 4096) {
		return sched::NOID;
	};
	for (let i = 0z; i < len(b); i += 1) {
		const p = (ARG + (i: uintptr)): *u8;
		*p = b[i];
	};

	return sched::spawn_user(user::entry: uintptr, STACK, ARG, len(b));
};
