use architecture;

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
	for (let i = 0; i < 100000 && (architecture::inb(0x64) & 2) != 0; i += 1) {
		architecture::pause();
	};
};

fn wait_read() void = {
	for (let i = 0; i < 100000 && (architecture::inb(0x64) & 1) == 0; i += 1) {
		architecture::pause();
	};
};

fn flush() void = {
	for (let i = 0; i < 64 && (architecture::inb(0x64) & 1) != 0; i += 1) {
		_ = architecture::inb(0x60);
	};
};

fn aux_write(v: u8) void = {
	wait_write();
	architecture::outb(0x64, 0xD4);
	wait_write();
	architecture::outb(0x60, v);
};

fn aux_reply() u8 = {
	wait_read();
	return architecture::inb(0x60);
};

export fn mouse_init() void = {
	flush();
	wait_write();
	architecture::outb(0x64, 0xA8);		// enable the auxiliary device
	wait_write();
	architecture::outb(0x64, 0x20);		// read the controller config
	const cfg = aux_reply();
	const ncfg = (cfg | 0x02) & ~(0x20: u8);	// IRQ12 on, clock on
	wait_write();
	architecture::outb(0x64, 0x60);		// write the config back
	wait_write();
	architecture::outb(0x60, ncfg);
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
	const st = architecture::inb(0x64);
	return (st & 1) != 0 && (st & 0x20) != 0;
};

// Packet assembly runs in whichever thread is waiting for input, and there can
// be more than one. A timer tick between two bytes of a packet would let the
// other thread read the rest and resynchronise on a data byte, so the whole
// parse holds interrupts off.
export fn mouse_poll() void = {
	const irq = architecture::irq_save();
	for (mouse_pending()) {
		const b = architecture::inb(0x60);
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
	architecture::irq_restore(irq);
};

export fn mouse_dx() int = {
	const irq = architecture::irq_save();
	const v = mouse_accx;
	mouse_accx = 0;
	architecture::irq_restore(irq);
	return v;
};

export fn mouse_dy() int = {
	const irq = architecture::irq_save();
	const v = mouse_accy;
	mouse_accy = 0;
	architecture::irq_restore(irq);
	return v;
};

export fn mouse_buttons() u8 = mouse_btns;

// ---------------------------------------------------------------------------
// The mouse as a program sees it, through /dev/mouse.
//
// Each event is one 64-bit word: the movement since the last one in the low
// 16 bits and the next 16, both signed, and the buttons at byte 4 with bit 0
// for the left button, 1 for the right and 2 for the middle. A word with no
// movement in it is still worth having when the buttons changed, and the
// buttons come as they are now rather than as edges, so a program that has
// missed a whole burst still knows what is down.
//
// Movement folds into the word waiting to be read while the buttons stay as
// they are, so a quick hand is never outrun by a game busy drawing a frame.

def MEVQ: size = 64;
let mq_dx: [MEVQ]int = [0...];
let mq_dy: [MEVQ]int = [0...];
let mq_b: [MEVQ]u8 = [0...];
let mhead = 0z;
let mn = 0z;

// Files mouse movement and the button state for the program that is drawing.
export fn mouse_note(dx: int, dy: int, b: u8) void = {
	const irq = architecture::irq_save();
	if (mn > 0) {
		const t = (mhead + mn - 1) % MEVQ;
		if (mq_b[t] == b && (dx != 0 || dy != 0)) {
			let x = mq_dx[t] + dx;
			let y = mq_dy[t] + dy;
			// A word holds 16 bits of each; past that the excess is dropped
			// rather than allowed to wrap into the wrong direction.
			if (x > 32767) {
				x = 32767;
			};
			if (x < -32768) {
				x = -32768;
			};
			if (y > 32767) {
				y = 32767;
			};
			if (y < -32768) {
				y = -32768;
			};
			mq_dx[t] = x;
			mq_dy[t] = y;
			architecture::irq_restore(irq);
			return;
		};
	};
	if (mn == MEVQ) {
		// Nobody is reading fast enough. The oldest word goes, so what is
		// missing is the movement rather than the buttons.
		mhead = (mhead + 1) % MEVQ;
		mn -= 1;
	};
	const t = (mhead + mn) % MEVQ;
	mq_dx[t] = dx;
	mq_dy[t] = dy;
	mq_b[t] = b;
	mn += 1;
	architecture::irq_restore(irq);
};

// The next word, or false when no event is waiting: a program polls this
// between frames rather than blocking on it.
export fn mouseev(out: *u64) bool = {
	const irq = architecture::irq_save();
	if (mn == 0) {
		architecture::irq_restore(irq);
		return false;
	};
	const i = mhead;
	*out = ((mq_dx[i]: u64) & 0xFFFF)
		| (((mq_dy[i]: u64) & 0xFFFF) << 16)
		| (((mq_b[i]: u64) & 0xFF) << 32);
	mhead = (mhead + 1) % MEVQ;
	mn -= 1;
	architecture::irq_restore(irq);
	return true;
};
