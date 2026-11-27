use architecture;
use session;
use sched;
use rt;

let lastbtn: u8 = 0;
let in_poll = false;

// Everything goes to both screens. The serial port carries the bytes straight
// through for a terminal to interpret; the compositor draws them in the
// terminal it owns, interpreting the escape sequences itself.
//
// The window manager draws the cell that changed and pushes just that cell, so
// a letter appears at once. Redrawing the whole frame here instead would mean
// copying three megabytes for every character, which is why output used to
// arrive in batches: the frame was only drawn once the program next waited for
// a key. Repainting is still left to the window manager for the moments when
// the picture really does change all over, such as a scroll or a resize.
export fn putc(ch: u8) void = {
	serial_putc(ch);
	vga_putc(ch);
	session::putc(ch, session::target());
};

// The size of the console, so a program can lay itself out to fit. With the
// window manager running that is the terminal window a program draws into;
// without it there is only the text console to measure.
export fn screen_rows() size = {
	return vga_rows();
};

export fn screen_cols() size = {
	return vga_cols();
};

// Draws whatever has been written to the screen since the last frame.
export fn sync() void = {
	// The window manager now draws on its own schedule.
	void;
};

// Vector 33 is the keyboard. Taking its scancode here, rather than when a
// program asks for input, is what keeps keystrokes from being lost.
export fn irq(vec: u64) void = {
	if (vec == 33) {
		keyboard_irq();
	};
};


export fn write(buf: []u8) size = {
	for (let i = 0z; i < len(buf); i += 1) {
		putc(buf[i]);
	};
	return len(buf);
};

export fn write_raw(addr: uintptr, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		putc(*((addr + (i: uintptr)): *u8));
	};
};

export fn print(s: str) void = {
	write(*(&s: *[]u8));
};

export fn println(s: str) void = {
	print(s);
	putc('\n': u8);
};

export fn clear() void = {
	vga_clear();
};

// A register dump is only readable in hex, and the decimal form of a fault
// address says nothing about which address was meant.
const hexchars: [16]u8 = ['0', '1', '2', '3', '4', '5', '6', '7',
	'8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];

export fn printhex(n: u64) void = {
	let buf: [16]u8 = [0...];
	let i = len(buf);
	if (n == 0) {
		i -= 1;
		buf[i] = '0': u8;
	} else {
		let v = n;
		for (v > 0) {
			i -= 1;
			buf[i] = hexchars[v % 16]: u8;
			v /= 16;
		};
	};
	for (let j = i; j < len(buf); j += 1) {
		putc(buf[j]);
	};
};

export fn printnum(n: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	if (n == 0) {
		i -= 1;
		buf[i] = '0': u8;
	} else {
		for (n > 0) {
			i -= 1;
			buf[i] = ((n % 10): u8) + ('0': u8);
			n /= 10;
		};
	};
	write(buf[i..]);
};

export fn getch() u8 = {
	for (true) {
		if (serial_has_data()) {
			return serial_getc();
		};
		if (keyboard_has_data()) {
			const ch = keyboard_getc();
			if (ch != 0) {
				return ch;
			};
		};
		architecture::pause();
	};
};

// Moves the pointer along with whatever the waiting loop is doing. More than
// one thread can be waiting for input, so a guard keeps a preempted draw from
// being interleaved by another one.
export fn poll_mouse() void = {
	const irq = architecture::irq_save();
	if (in_poll) {
		architecture::irq_restore(irq);
		return;
	};
	in_poll = true;
	architecture::irq_restore(irq);
	mouse_poll();
	const dx = mouse_dx();
	const dy = mouse_dy();
	const b = mouse_buttons();
	// Pointer edges belong to the window manager, which reads them from
	// /dev/mouse. Every edge is put in that queue now; the manager decides
	// whether it is a menu click, a drag, or a button for a drawing program.
	if (dx != 0 || dy != 0 || b != lastbtn) {
		mouse_note(dx, dy, b);
		lastbtn = b;
	};
	in_poll = false;
};

// Returns one byte for a program that is reading characters, or zero when
// nothing is waiting. A PS/2 scancode is filed against the thread that owned
// the keyboard when it arrived; a byte from the serial terminal is filed here,
// since that is the only moment its owner is known.
export fn pollch() u8 = {
	if (serial_has_data()) {
		const b = serial_getc();
		sched::queue_input_to(sched::focus_thread(), b);
		return b;
	};
	if (keyboard_has_data()) {
		return keyboard_getc();
	};
	return 0;
};

// The next key edge for a program that draws rather than types: the scancode
// with KEY_UP when the key was released. Zero when none is waiting. This is
// what /dev/kbd serves.
export fn keyev() u64 = {
	return keyboard_keyev();
};

@init fn init() void = {
	// The machine checks the permission for input and output against the
	// task state segment, and there is none until it is set up.
	architecture::tss_init();
	architecture::outb(0x3F8, 0x43);
	serial_init();
	vga_init();
	mouse_init();
	keyboard_init();
	rt::con_write = &write;
};
