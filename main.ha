use arch;
use block;
use boot;
use console;
use fb;
use fs;
use kit;
use loader;
use mem;
use paging;
use rt;
use sched;
use shell;
use sys;
use syscall;

fn on_fault(regs: *arch::registers) uintptr = {
	console::print("\nexception ");
	console::printnum(regs.vector);
	console::print(" error ");
	console::printnum(regs.error);
	console::print(" at ");
	console::printnum(regs.rip);
	console::putc('\n');
	if ((regs.cs & 3) == 3) {
		console::println("killing user process");
		return sched::fault_kill();
	};
	return 0;
};

export @symbol("main") fn main(mbi: uintptr) void = {
	if (mbi == 0) {
		console::println("bunix: no multiboot information");
		rt::halt();
	};

	const mb = boot::at(mbi);
	let mem_mib = 0u64;
	if ((mb.flags & boot::FLAG_MMAP) != 0) {
		mem_mib = boot::available(mb) / (1024 * 1024);
	};

	mem::init(mb);
	loader::reserve();
	paging::init();
	fb::init(mb);
	if (!fb::active()) {
		fb::vbe();
	};
	kit::begin();

	if (fb::active()) {
		console::print("video:     ");
		console::printnum(fb::width());
		console::print("x");
		console::printnum(fb::height());
		console::println("");
	};

	console::print(sys::NAME);
	console::print(" ");
	console::println(sys::VERSION);
	console::println("");

	if ((mb.flags & boot::FLAG_MEMORY) != 0) {
		console::print("memory:    ");
		console::printnum(mb.mem_lower);
		console::print(" KiB low, ");
		console::printnum(mb.mem_upper);
		console::println(" KiB high");
	};

	if ((mb.flags & boot::FLAG_MMAP) != 0) {
		console::print("available: ");
		console::printnum(mem_mib);
		console::println(" MiB");
	};

	fs::init();
	console::print("frames:    ");
	console::printnum(mem::free_frames());
	console::print(" free of ");
	console::printnum(mem::total_frames());
	console::println("");

	console::print("disk:      ");
	if (block::present_drive()) {
		console::print("present, ");
		console::printnum(block::nsect());
		console::println(" sectors");
	} else {
		console::println("none");
	};

	arch::fault_hook = &on_fault;
	arch::idt_init();
	arch::pic_remap();
	arch::timer_init();
	arch::pic_unmask(0);
	arch::tss_init();

	console::println("");
	console::println("starting user init.");
	syscall::init();
	sched::start();
	arch::sched_hook = &sched::tick;
	arch::sti();

	const init_id = loader::run("/sh");
	console::println("");
	shell::monitor(init_id);
};
