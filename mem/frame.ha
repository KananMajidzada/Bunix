use boot;

@symbol("_kernel_end") const kernel_end: [*]u8;

def PAGE: uintptr = 4096;

let base: uintptr = 0;
let nframes: u64 = 0;

fn byte(i: u64) *u8 = {
	return (base + (i >> 3): uintptr): *u8;
};

fn test(i: u64) bool = {
	const b = byte(i);
	return (*b & (1: u8 << ((i & 7): u8))) != 0;
};

fn set(i: u64) void = {
	const b = byte(i);
	*b |= 1: u8 << ((i & 7): u8);
};

fn clear(i: u64) void = {
	const b = byte(i);
	*b &= ~(1: u8 << ((i & 7): u8));
};

export fn init(mb: *boot::info) void = {
	const top = 0x100000 + (mb.mem_upper: u64) * 1024;
	nframes = top / (PAGE: u64);
	const bytes = (nframes + 7) / 8;

	base = (&kernel_end: uintptr + PAGE - 1) & ~(PAGE - 1);

	// Start with every frame claimed.
	let p = base;
	const bend = base + (bytes: uintptr);
	for (p < bend) {
		*(p: *u8) = 0xFF;
		p += 1;
	};

	// Release what the boot loader called available.
	if ((mb.flags & boot::FLAG_MMAP) != 0) {
		let q = mb.mmap_addr: uintptr;
		const mend = q + (mb.mmap_length: uintptr);
		for (q < mend) {
			const e = q: *boot::mmap_entry;
			if (e.typ == boot::TYPE_AVAILABLE) {
				const lo = e.base / (PAGE: u64);
				let hi = (e.base + e.length) / (PAGE: u64);
				if (hi > nframes) {
					hi = nframes;
				};
				for (let i = lo; i < hi; i += 1) {
					clear(i);
				};
			};
			q += (e.sz + 4): uintptr;
		};
	};

	// Reclaim low memory, the kernel, and the bitmap itself.
	const reserved = (((bend + PAGE - 1) & ~(PAGE - 1)) / PAGE): u64;
	for (let i = 0u64; i < reserved; i += 1) {
		set(i);
	};
};

// Returns the physical address of a free frame, or zero when none remain.
export fn frame_alloc() uintptr = {
	for (let i = 0u64; i < nframes; i += 1) {
		if (!test(i)) {
			set(i);
			return (i * (PAGE: u64)): uintptr;
		};
	};
	return 0;
};

// Allocates count contiguous frames and returns the physical base, or zero.
export fn frames_alloc(count: u64) uintptr = {
	if (count == 0) {
		return 0;
	};
	let run = 0u64;
	let start = 0u64;
	for (let i = 0u64; i < nframes; i += 1) {
		if (test(i)) {
			run = 0;
			continue;
		};
		if (run == 0) {
			start = i;
		};
		run += 1;
		if (run == count) {
			for (let j = start; j < start + count; j += 1) {
				set(j);
			};
			return (start * (PAGE: u64)): uintptr;
		};
	};
	return 0;
};

export fn release(addr: uintptr) void = {
	clear((addr / PAGE): u64);
};

// Marks a physical range as in use, so the allocator keeps it for something
// else. Used to hold back the fixed region user programs are loaded into.
export fn reserve(base: uintptr, count: u64) void = {
	const lo = (base / PAGE): u64;
	if (lo >= nframes) {
		return;
	};
	let hi = ((base + (count: uintptr)) / PAGE): u64;
	if (hi > nframes) {
		hi = nframes;
	};
	for (let i = lo; i < hi; i += 1) {
		set(i);
	};
};

export fn free_frames() u64 = {
	let n = 0u64;
	for (let i = 0u64; i < nframes; i += 1) {
		if (!test(i)) {
			n += 1;
		};
	};
	return n;
};

export fn total_frames() u64 = nframes;
