// Programmable interval timer, channel 0, used as the system clock.

def HZ: u32 = 100;

let tick: u64 = 0;

export fn timer_init() void = {
	const divisor = 1193182 / HZ;
	outb(0x43, 0x36);			// channel 0, mode 3, binary
	outb(0x40, (divisor & 0xFF): u8);
	outb(0x40, ((divisor >> 8) & 0xFF): u8);
};

export fn timer_tick() void = {
	tick += 1;
};

export fn ticks() u64 = tick;

export fn seconds() u64 = tick / HZ;
