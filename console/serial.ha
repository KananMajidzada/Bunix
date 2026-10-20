use architecture;

def COM1: u16 = 0x3F8;

// Bring up COM1 at 115200 baud, 8N1, with the FIFOs enabled.
export fn serial_init() void = {
	architecture::outb(COM1 + 1, 0x00);	// no interrupts
	architecture::outb(COM1 + 3, 0x80);	// divisor latch
	architecture::outb(COM1 + 0, 0x01);	// divisor low, 115200 baud
	architecture::outb(COM1 + 1, 0x00);	// divisor high
	architecture::outb(COM1 + 3, 0x03);	// 8 bits, no parity, one stop
	architecture::outb(COM1 + 2, 0x01);	// enable FIFOs, keep the receive queue
};

export fn serial_putc(ch: u8) void = {
	if (ch == '\n': u8) {
		serial_out('\r': u8);
	};
	serial_out(ch);
};

fn serial_out(ch: u8) void = {
	for ((architecture::inb(COM1 + 5) & 0x20) == 0) void;
	architecture::outb(COM1, ch);
};

// Waits until everything written has actually left the port. The transmit
// register being empty only means the next byte can be handed to it; the
// shift register and the FIFO behind it can still be holding a good many, and
// a line typed at a shell that reboots is exactly the thing that would be
// lost. Bit six of the line status register says both are empty.
export fn serial_flush() void = {
	for ((architecture::inb(COM1 + 5) & 0x40) == 0) void;
};

export fn serial_has_data() bool = {
	return (architecture::inb(COM1 + 5) & 1) != 0;
};

export fn serial_getc() u8 = {
	for ((architecture::inb(COM1 + 5) & 1) == 0) void;
	return architecture::inb(COM1);
};
