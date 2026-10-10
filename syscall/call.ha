use arch;
use console;
use sched;

export def WRITE: u64 = 1;
export def EXIT: u64 = 0;

export fn init() void = {
	arch::syscall_hook = &handle;
};

fn handle(regs: *arch::registers) uintptr = {
	switch (regs.rax) {
	case EXIT =>
		sched::retire();
		return sched::tick(regs);
	case WRITE =>
		console::write_raw(regs.rdi: uintptr, regs.rsi: size);
		regs.rax = regs.rsi;
		return regs: uintptr;
	case =>
		regs.rax = 0xFFFFFFFFFFFFFFFF;
		return regs: uintptr;
	};
};
