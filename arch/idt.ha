use rt;

@symbol("arch.isr_stubs") const isr_stubs: [*]uintptr;

export def SYSCALL: size = 128;

export let fault_hook: nullable *fn(regs: *registers) void = null;
export let irq_hook: nullable *fn(vec: u64) void = null;

// Register save area built on the stack by isr_common, in push order.
export type registers = struct {
	r15: u64, r14: u64, r13: u64, r12: u64,
	r11: u64, r10: u64, r9: u64, r8: u64,
	rbp: u64, rdi: u64, rsi: u64, rdx: u64,
	rcx: u64, rbx: u64, rax: u64,
	vector: u64, error: u64,
	rip: u64, cs: u64, rflags: u64, rsp: u64, ss: u64,
};

export let sched_hook: nullable *fn(regs: *registers) uintptr = null;
export let syscall_hook: nullable *fn(regs: *registers) uintptr = null;

type gate = struct @packed {
	off_low: u16,
	sel: u16,
	ist: u8,
	type_attr: u8,
	off_mid: u16,
	off_high: u32,
	zero: u32,
};

type idtr = struct @packed {
	limit: u16,
	base: u64,
};

let gates: [256]gate = [gate {
	off_low = 0, sel = 0, ist = 0, type_attr = 0,
	off_mid = 0, off_high = 0, zero = 0,
}...];

fn load_idt(p: *idtr) void;

export fn idt_init() void = {
	for (let i = 0z; i < 256; i += 1) {
		const addr = isr_stubs[i];
		gates[i] = gate {
			off_low = (addr & 0xFFFF): u16,
			sel = 0x08,
			ist = 0,
			type_attr = if (i == SYSCALL) 0xEE else 0x8E,
			off_mid = ((addr >> 16) & 0xFFFF): u16,
			off_high = (addr >> 32): u32,
			zero = 0,
		};
	};
	let p = idtr {
		limit = (256 * 16 - 1): u16,
		base = &gates: uintptr,
	};
	load_idt(&p);
};

export fn isr_handler(regs: *registers) uintptr = {
	const v = regs.vector;
	if (v < 32) {
		match (fault_hook) {
		case null => void;
		case let f: *fn(regs: *registers) void =>
			f(regs);
		};
		rt::halt();
	} else if (v == 0xFF) {
		rt::halt();
	} else if (v == (SYSCALL: u64)) {
		return dispatch(syscall_hook, regs);
	} else {
		if (v == 32) {
			timer_tick();
		};
		match (irq_hook) {
		case null => void;
		case let f: *fn(vec: u64) void =>
			f(v);
		};
		if (v >= 40) {
			outb(0xA0, 0x20);
		};
		outb(0x20, 0x20);
		if (v == 32) {
			return dispatch(sched_hook, regs);
		};
	};
	return regs: uintptr;
};

fn dispatch(hook: nullable *fn(regs: *registers) uintptr, regs: *registers) uintptr = {
	let frame = regs: uintptr;
	match (hook) {
	case null => void;
	case let f: *fn(regs: *registers) uintptr =>
		frame = f(regs);
	};
	return frame;
};
