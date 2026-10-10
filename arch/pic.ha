// 8259 programmable interrupt controller. The BIOS maps the two chips over the
// CPU exception vectors, so we relocate them to 32 and 40 first.

export fn pic_remap() void = {
	outb(0x20, 0x11); io_wait();
	outb(0xA0, 0x11); io_wait();
	outb(0x21, 0x20); io_wait();	// master vectors start at 32
	outb(0xA1, 0x28); io_wait();	// slave vectors start at 40
	outb(0x21, 0x04); io_wait();	// slave on IRQ2
	outb(0xA1, 0x02); io_wait();
	outb(0x21, 0x01); io_wait();	// 8086 mode
	outb(0xA1, 0x01); io_wait();
	outb(0x21, 0xFF);		// mask everything for now
	outb(0xA1, 0xFF);
};

export fn pic_unmask(irq: u8) void = {
	if (irq < 8) {
		outb(0x21, inb(0x21) & ~(1: u8 << irq));
	} else {
		outb(0xA1, inb(0xA1) & ~(1: u8 << (irq - 8)));
		outb(0x21, inb(0x21) & ~(1: u8 << 2));
	};
};
