use architecture;

// The PC speaker: a square wave on the PIT's second channel, let out
// through the speaker gate on port 0x61. It is a beeper, not a sound
// card - one pitch at a time, no volume and no samples. The card comes
// later; this is the hardware a tune needs to reach the ear at all, and
// a program asks for it by writing the tune to /dev/speaker.
//
// A tone takes as long as it is asked to take, and while it plays the
// clock keeps ticking: every tick the scheduler runs some other thread,
// so a melody holds up nothing but the program that asked for it.

// tone plays freq hertz for ms milliseconds and comes back when the
// note is over. A freq of zero is a rest: quiet for the length of the
// note.
export fn tone(freq: u64, ms: u64) void = {
	if (ms == 0) {
		return;
	};
	if (freq == 0) {
		silence();
		wait_ms(ms);
		return;
	};
	// The PIT counts at 1193182 Hz, so the divisor is the pitch: how
	// many ticks of its clock make one wave. Channel 2 takes its reload
	// low byte first and then high, in square wave mode.
	let div = 1193182 / freq;
	if (div < 1) {
		div = 1;
	};
	if (div > 65535) {
		div = 65535;
	};
	architecture::outb(0x43, 0xB6);
	architecture::outb(0x42, (div & 0xFF): u8);
	architecture::outb(0x42, ((div >> 8) & 0xFF): u8);
	// Let the counter out and connect it to the speaker.
	const gate = architecture::inb(0x61);
	architecture::outb(0x61, gate | 0x03);
	wait_ms(ms);
	silence();
};

// The speaker off. The counter keeps its state, so the next note's
// reload starts the next pitch from where this one stopped.
fn silence() void = {
	architecture::outb(0x61, architecture::inb(0x61) & 0xFC);
};

// Wait out one note. The syscall arrived through an interrupt gate,
// which holds interrupts off for its whole length; left that way the
// clock would not tick and this wait would never end. Let them back on
// for the wait: the timer runs, the scheduler takes this thread away
// between ticks and gives the machine to someone else, and the flags
// the syscall returns with are the ones it came with.
fn wait_ms(ms: u64) void = {
	architecture::sti();
	const end = architecture::millis() + ms;
	for (architecture::millis() < end) void;
	architecture::cli();
};
