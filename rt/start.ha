@symbol("main") fn main(mbi: uintptr) void;

@symbol("__init_array_start") const init_start: [*]*fn() void;
@symbol("__init_array_end") const init_end: [*]*fn() void;
@symbol("__fini_array_start") const fini_start: [*]*fn() void;
@symbol("__fini_array_end") const fini_end: [*]*fn() void;
@symbol("__bss_start") const bss_start: [*]u8;
@symbol("__bss_end") const bss_end: [*]u8;
@symbol("__data_start") const data_start: [*]u8;
@symbol("__data_end") const data_end: [*]u8;
@symbol("_kernel_end") const kernel_end: [*]u8;
@symbol("__image_end") const image_end: [*]u8;

// The data section is copied aside before anything writes to it, so that the
// machine can hand out a copy of itself that is the same as the one that was
// loaded. That is what the installer writes to a disk.
def DATACOPY: size = 512 * 1024;

let data_copy: [DATACOPY]u8 = [0...];
// Whether the data section fitted in the room there was.
let data_ok: bool = false;

// Entered from rt/start.s once the CPU is in long mode.
export fn start_hare(mbi: uintptr) never = {
	// The data section is copied before the init functions run, since
	// they are allowed to write to it.
	const ds = &data_start: uintptr;
	const de = &data_end: uintptr;
	const n = de - ds;
	if (n <= DATACOPY) {
		for (let i = 0z; i < n; i += 1) {
			data_copy[i] = data_start[i];
		};
		data_ok = true;
	};

	const ninit = (&init_end: uintptr - &init_start: uintptr): size
		/ size(*fn() void);
	for (let i = 0z; i < ninit; i += 1) {
		init_start[i]();
	};

	main(mbi);

	const nfini = (&fini_end: uintptr - &fini_start: uintptr): size
		/ size(*fn() void);
	for (let i = nfini; i > 0; i -= 1) {
		fini_start[i - 1]();
	};

	halt();
};

// Where the kernel was loaded, and how much of it there is. The kernel is
// linked and loaded at 64 MiB, above the user window, so that the per-space
// pages at 4..36 MiB never shadow the kernel's own.
export fn image_base() uintptr = {
	return 0x04000000;
};

export fn image_size() uintptr = {
	return (&image_end: uintptr) - image_base();
};

// The kernel's own image, as it was loaded. The data section is served from
// the copy that was made at the start, since the one in memory has been
// written to since. The bytes are read from an offset, the way a disk is.
export fn image(buf: []u8, off: u64, n: size) size = {
	const base = image_base();
	const end = &image_end: uintptr;
	const ds = &data_start: uintptr;
	const de = &data_end: uintptr;
	let got = 0z;
	for (got < n) {
		const at = base + (off + (got: u64)): uintptr;
		if (at >= end) {
			break;
		};
		let b = *(at: *u8);
		if (data_ok && at >= ds && at < de) {
			b = data_copy[at - ds];
		};
		buf[got] = b;
		got += 1;
	};
	return got;
};
