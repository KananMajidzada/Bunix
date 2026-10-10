use boot;
use console;
use rt;
use shell;

// Kernel entry. The runtime calls this once the CPU is in long mode and the
// @init hooks have run; mbi is the physical address of the Multiboot
// information, or zero if there was none.
export @symbol("main") fn main(mbi: uintptr) void = {
	console::println("Bunix, a native Plan 9-shaped system");
	console::println("");

	if (mbi == 0) {
		console::println("bunix: no multiboot information");
		rt::halt();
	};

	const mb = boot::at(mbi);
	if ((mb.flags & boot::FLAG_MEMORY) != 0) {
		console::print("memory:    ");
		console::printnum(mb.mem_lower);
		console::print(" KiB low, ");
		console::printnum(mb.mem_upper);
		console::println(" KiB high");
	};

	let mem_mib = 0u64;
	if ((mb.flags & boot::FLAG_MMAP) != 0) {
		mem_mib = boot::available(mb) / (1024 * 1024);
		console::print("available: ");
		console::printnum(mem_mib);
		console::println(" MiB");
	};

	console::println("");
	console::println("type 'help' for commands.");
	shell::run(mem_mib);
};
