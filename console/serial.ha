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

export fn serial_has_data() bool = {
	return (architecture::inb(COM1 + 5) & 1) != 0;
};

export fn serial_getc() u8 = {
	for ((architecture::inb(COM1 + 5) & 1) == 0) void;
	return architecture::inb(COM1);
};
