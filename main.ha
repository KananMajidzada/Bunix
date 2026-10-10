use arch;
use boot;
use console;
use fs;
use loader;
use mem;
use rt;
use sched;
use shell;
use sys;
use syscall;

fn on_fault(regs: *arch::registers) void = {
	console::print("\nexception ");
	console::printnum(regs.vector);
	console::print(" error ");
	console::printnum(regs.error);
	console::print(" at ");
	console::printnum(regs.rip);
	console::putc('\n');
	rt::halt();
};

export @symbol("main") fn main(mbi: uintptr) void = {
	console::print(sys::NAME);
	console::print(" ");
	console::println(sys::VERSION);
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

	mem::init(mb);
	loader::reserve();
	fs::init();
	console::print("frames:    ");
	console::printnum(mem::free_frames());
	console::print(" free of ");
	console::printnum(mem::total_frames());
	console::println("");

	arch::fault_hook = &on_fault;
	arch::idt_init();
	arch::pic_remap();
	arch::timer_init();
	arch::pic_unmask(0);
	arch::tss_init();
	syscall::init();
	sched::start();
	arch::sched_hook = &sched::tick;
	arch::sti();

	console::println("");
	console::println("type 'help' for commands.");
	shell::run(mem_mib);
};
