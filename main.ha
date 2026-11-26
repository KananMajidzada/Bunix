use architecture;
use block;
use boot;
use console;
use debug;
use fb;
use fs;
use loader;
use mem;
use paging;
use rt;
use sched;
use shell;
use sound;
use sys;
use syscall;

fn on_fault(regs: *architecture::registers) uintptr = {
	if ((regs.cs & 3) == 3) {
		// A fault in user space is usually one address that was meant for
		// something else, and the decimal form says nothing about which.
		console::print("\nexception ");
		console::printnum(regs.vector);
		console::print(" at ");
		console::printnum(regs.rip);
		console::putc('\n');
		console::print("  rip=");
		console::printhex(regs.rip);
		console::print(" rsp=");
		console::printhex(regs.rsp);
		console::print(" rbp=");
		console::printhex(regs.rbp);
		console::print(" rdi=");
		console::printhex(regs.rdi);
		console::print(" rsi=");
		console::printhex(regs.rsi);
		console::print(" rax=");
		console::printhex(regs.rax);
		console::print(" cr2=");
		console::printhex(architecture::fault_address());
		console::putc('\n');
		console::println("killing user process");
		return sched::fault_kill();
	};
	debug::fault(regs);
};

// An interrupt may be the keyboard's, the card's, or one of the things
// added later. Each module looks at the line and ignores the ones that are
// not its own.
fn on_irq(vec: u64) void = {
	console::irq(vec);
	sound::audio_irq(vec);
};

export @symbol("main") fn main(mbi: uintptr) void = {
	if (mbi == 0) {
		debug::panic("no multiboot information");
	};

	// A mark on the serial line with the information the kernel was
	// given, to see that it arrived.
	architecture::outb(0x3F8, 0x21);
	architecture::outb(0x3F8, 0x0D);
	architecture::outb(0x3F8, 0x0A);
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
	sound::audio_init();
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

	console::print("audio:     ");
	if (sound::audio_present()) {
		console::print("sb16, irq ");
		console::printnum(sound::audio_irq_line());
	} else {
		console::print("none");
	};
	console::println("");

	architecture::fault_hook = &on_fault;
	architecture::idt_init();
	architecture::pic_remap();
	architecture::timer_init();
	architecture::irq_hook = &on_irq;
	architecture::pic_unmask(0);
	architecture::pic_unmask(1);
	if (sound::audio_present()) {
		architecture::pic_unmask(sound::audio_irq_line());
	};
	architecture::tss_init();
	sched::fpu_init();

	console::println("");
	console::println("starting user init.");
	syscall::init();
	sched::start();
	architecture::sched_hook = &sched::tick;
	architecture::sti();

	// The window manager is a program too. It takes over the screen before
	// the shell starts writing into its first terminal.
	_ = loader::run("/wm");
	const init_id = loader::run("/sh");
	sched::bind_shell(init_id, 0);
	console::println("");
	shell::monitor(init_id);
};
