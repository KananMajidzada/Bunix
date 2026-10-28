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

// Milliseconds since boot, for a program that paces itself: a game loop asks
// for this rather than counting its own iterations, so it runs at the same
// speed on a fast machine and a slow one. The timer ticks HZ times a second,
// so this is whole multiples of (1000 / HZ).
export fn millis() u64 = {
	return tick * (1000 / (HZ: u64));
};
