@symbol("main") fn main() void;

@symbol("__init_array_start") const init_start: [*]*fn() void;
@symbol("__init_array_end") const init_end: [*]*fn() void;
@symbol("__fini_array_start") const fini_start: [*]*fn() void;
@symbol("__fini_array_end") const fini_end: [*]*fn() void;
@symbol("__bss_start") const bss_start: [*]u8;
@symbol("__bss_end") const bss_end: [*]u8;

export fn start_hare() never = {
	const bs = &bss_start: uintptr;
	const be = &bss_end: uintptr;
	for (let p = bs; p < be; p += 1) {
		*(p: *u8) = 0;
	};

	const ninit = (&init_end: uintptr - &init_start: uintptr): size
		/ size(*fn() void);
	for (let i = 0z; i < ninit; i += 1) {
		init_start[i]();
	};

	main();

	const nfini = (&fini_end: uintptr - &fini_start: uintptr): size
		/ size(*fn() void);
	for (let i = nfini; i > 0; i -= 1) {
		fini_start[i - 1]();
	};

	exit();
};
