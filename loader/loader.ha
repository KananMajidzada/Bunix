use mem;
use sched;
use user;

export const BASE: uintptr = 0x400000;
export const SIZE: u64 = 0x400000;
export const STACK: uintptr = 0x7FF000;

export fn reserve() void = {
	mem::reserve(BASE, SIZE);
};

export fn run() size = {
	for (let i = 0z; i < len(user::prog); i += 1) {
		const p = (BASE + (i: uintptr)): *u8;
		*p = user::prog[i];
	};
	return sched::spawn_user(user::entry: uintptr, STACK);
};
