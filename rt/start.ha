// The kernel entry, provided by the program built against this runtime. It
// receives the physical address of the Multiboot information structure, or zero
// if we were not booted by a Multiboot loader.
@symbol("main") fn main(mbi: uintptr) void;

@symbol("__init_array_start") const init_start: [*]*fn() void;
@symbol("__init_array_end") const init_end: [*]*fn() void;
@symbol("__fini_array_start") const fini_start: [*]*fn() void;
@symbol("__fini_array_end") const fini_end: [*]*fn() void;

// Entered from rt/start.s once the CPU is in long mode.
export fn start_hare(mbi: uintptr) never = {
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
