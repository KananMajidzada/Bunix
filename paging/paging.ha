use arch;
use mem;

def ENTRY_P: u64 = 1;
def ENTRY_W: u64 = 2;
def ENTRY_U: u64 = 4;
def ENTRY_PS: u64 = 0x80;

let boot: uintptr = 0;

export fn init() void = {
	boot = arch::read_cr3();
};

export fn kernel() uintptr = boot;

export fn current() uintptr = arch::read_cr3();

fn zero(p: uintptr, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		*((p + (i: uintptr)): *u8) = 0;
	};
};

fn get(table: uintptr, i: u64) u64 = {
	const p = (table + (i * 8): uintptr): *u64;
	return *p;
};

fn set(table: uintptr, i: u64, v: u64) void = {
	const p = (table + (i * 8): uintptr): *u64;
	*p = v;
};

// A fresh address space: the kernel identity-mapped supervisor-only, with a
// private page table for the 2 MiB user window at 0x400000.
export fn space_new() uintptr = {
	const pml4 = mem::frames_alloc(1);
	const pdpt = mem::frames_alloc(1);
	const pd = mem::frames_alloc(1);
	const pt = mem::frames_alloc(1);
	if (pml4 == 0 || pdpt == 0 || pd == 0 || pt == 0) {
		return 0;
	};
	zero(pml4, 4096);
	zero(pdpt, 4096);
	zero(pd, 4096);
	zero(pt, 4096);

	for (let i = 0u64; i < 512; i += 1) {
		if (i == 2) {
			set(pd, i, (pt: u64) | ENTRY_P | ENTRY_W | ENTRY_U);
		} else {
			set(pd, i, (i * 0x200000) | ENTRY_P | ENTRY_W | ENTRY_PS);
		};
	};
	set(pdpt, 0, (pd: u64) | ENTRY_P | ENTRY_W | ENTRY_U);
	set(pml4, 0, (pdpt: u64) | ENTRY_P | ENTRY_W | ENTRY_U);
	return pml4;
};

export fn map_user(
	space: uintptr,
	vaddr: u64,
	paddr: uintptr,
	writable: bool,
) void = {
	const pml4_i = (vaddr >> 39) & 0x1FF;
	const pdpt_i = (vaddr >> 30) & 0x1FF;
	const pd_i = (vaddr >> 21) & 0x1FF;
	const pt_i = (vaddr >> 12) & 0x1FF;
	const pdpt = (get(space, pml4_i) & ~0xFFF): uintptr;
	const pd = (get(pdpt, pdpt_i) & ~0xFFF): uintptr;
	const pt = (get(pd, pd_i) & ~0xFFF): uintptr;
	let e = (paddr: u64) | ENTRY_P | ENTRY_U;
	if (writable) {
		e |= ENTRY_W;
	};
	set(pt, pt_i, e);
};

export fn flush(vaddr: u64) void = {
	arch::invlpg(vaddr: uintptr);
};

export fn leave(space: uintptr) void = {
	arch::write_cr3(space);
};

// Frees every frame mapped in the user window plus the page tables of the
// address space itself. Never call this on the space while it is loaded.
export fn space_free(space: uintptr) void = {
	const pml4 = space;
	const pdpt = (get(pml4, 0) & ~0xFFF): uintptr;
	const pd = (get(pdpt, 0) & ~0xFFF): uintptr;
	const pt = (get(pd, 2) & ~0xFFF): uintptr;
	for (let i = 0u64; i < 512; i += 1) {
		const e = get(pt, i);
		if ((e & ENTRY_P) != 0 && (e & ENTRY_U) != 0) {
			mem::release((e & ~0xFFF): uintptr);
		};
	};
	mem::release(pt);
	mem::release(pd);
	mem::release(pdpt);
	mem::release(pml4);
};
