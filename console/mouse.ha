use arch;

// PS/2 mouse on the auxiliary port of the i8042 controller. We poll it from
// the input paths rather than taking IRQ12, so the pointer moves whenever the
// machine is waiting for a key. Three-byte packets carry sign deltas and the
// button bits; we accumulate them until the window manager reads them.

let mouse_ready = false;
let mouse_got = 0z;
let mouse_packet: [3]u8 = [0...];
let mouse_accx = 0;
let mouse_accy = 0;
let mouse_btns: u8 = 0;

fn wait_write() void = {
	for (let i = 0; i < 100000 && (arch::inb(0x64) & 2) != 0; i += 1) {
		arch::pause();
	};
};

fn wait_read() void = {
	for (let i = 0; i < 100000 && (arch::inb(0x64) & 1) == 0; i += 1) {
		arch::pause();
	};
};

fn flush() void = {
	for (let i = 0; i < 64 && (arch::inb(0x64) & 1) != 0; i += 1) {
		_ = arch::inb(0x60);
	};
};

fn aux_write(v: u8) void = {
	wait_write();
	arch::outb(0x64, 0xD4);
	wait_write();
	arch::outb(0x60, v);
};

fn aux_reply() u8 = {
	wait_read();
	return arch::inb(0x60);
};

export fn mouse_init() void = {
	flush();
	wait_write();
	arch::outb(0x64, 0xA8);		// enable the auxiliary device
	wait_write();
	arch::outb(0x64, 0x20);		// read the controller config
	const cfg = aux_reply();
	const ncfg = (cfg | 0x02) & ~(0x20: u8);	// IRQ12 on, clock on
	wait_write();
	arch::outb(0x64, 0x60);		// write the config back
	wait_write();
	arch::outb(0x60, ncfg);
	aux_write(0xF6);		// set defaults
	_ = aux_reply();
	aux_write(0xF4);		// enable data reporting
	_ = aux_reply();
	mouse_got = 0;
	mouse_ready = true;
};

fn mouse_pending() bool = {
	if (!mouse_ready) {
		return false;
	};
	const st = arch::inb(0x64);
	return (st & 1) != 0 && (st & 0x20) != 0;
};

// Packet assembly runs in whichever thread is waiting for input, and there can
// be more than one. A timer tick between two bytes of a packet would let the
// other thread read the rest and resynchronise on a data byte, so the whole
// parse holds interrupts off.
export fn mouse_poll() void = {
	const irq = arch::irq_save();
	for (mouse_pending()) {
		const b = arch::inb(0x60);
		if (mouse_got == 0 && (b & 0x08) == 0) {
			continue;	// a stale byte; wait for a packet head
		};
		mouse_packet[mouse_got] = b;
		mouse_got += 1;
		if (mouse_got == 3) {
			mouse_got = 0;
			const flags = mouse_packet[0];
			let dx = mouse_packet[1]: int;
			let dy = mouse_packet[2]: int;
			if ((flags & 0x10) != 0) {
				dx -= 256;
			};
			if ((flags & 0x20) != 0) {
				dy -= 256;
			};
			mouse_accx += dx;
			mouse_accy -= dy;	// screen y grows downward
			mouse_btns = flags & 0x07;
		};
	};
	arch::irq_restore(irq);
};

export fn mouse_dx() int = {
	const irq = arch::irq_save();
	const v = mouse_accx;
	mouse_accx = 0;
	arch::irq_restore(irq);
	return v;
};

export fn mouse_dy() int = {
	const irq = arch::irq_save();
	const v = mouse_accy;
	mouse_accy = 0;
	arch::irq_restore(irq);
	return v;
};

export fn mouse_buttons() u8 = mouse_btns;
