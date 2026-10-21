use architecture;
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

fn on_fault(regs: *architecture::registers) uintptr = {
	console::print("\nexception ");
	console::printnum(regs.vector);
	console::print(" error ");
	console::printnum(regs.error);
	console::print(" at ");
	console::printnum(regs.rip);
	console::print(" addr ");
	console::printnum(architecture::fault_address());
	console::putc('\n');
	if ((regs.cs & 3) == 3) {
		// A fault in user space is usually one address that was meant for
		// something else, and the decimal form says nothing about which.
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
	console::println("kernel fault, halting");
	rt::halt();
};

// A terminal window is no use empty, so one opened from the menu gets its own
// shell rather than a second prompt appearing in the window it was opened over.
fn on_new_win(wi: size) void = {
	// The window is named before the shell starts, because the shell prints
	// its banner as soon as it runs. The shell is started sharing the
	// filesystem rather than with a namespace of its own, so that a file
	// written in one terminal is visible from another: separate terminals,
	// one machine.
	sched::set_spawn_win(wi);
	const id = loader::run("/sh");
	sched::bind_shell(id, wi);
};

export @symbol("main") fn main(mbi: uintptr) void = {
	if (mbi == 0) {
		console::println("bunix: no multiboot information");
		rt::halt();
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
	kit::new_win_hook = &on_new_win;
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

	architecture::fault_hook = &on_fault;
	architecture::idt_init();
	architecture::pic_remap();
	architecture::timer_init();
	architecture::irq_hook = &console::irq;
	architecture::pic_unmask(0);
	architecture::pic_unmask(1);
	architecture::tss_init();
	sched::fpu_init();

	console::println("");
	console::println("starting user init.");
	syscall::init();
	sched::start();
	architecture::sched_hook = &sched::tick;
	architecture::sti();

	const init_id = loader::run("/sh");
	sched::bind_shell(init_id, 0);
	console::println("");
	shell::monitor(init_id);
};
