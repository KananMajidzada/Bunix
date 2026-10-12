use arch;
use kit;
use rt;

let lastbtn: u8 = 0;

export fn putc(ch: u8) void = {
	serial_putc(ch);
	vga_putc(ch);
	kit::putc(ch);
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
		poll_mouse();
		if (serial_has_data()) {
			return serial_getc();
		};
		if (keyboard_has_data()) {
			const ch = keyboard_getc();
			if (ch != 0) {
				return ch;
			};
		};
		arch::pause();
	};
};

// Moves the pointer along with whatever the waiting loop is doing.
export fn poll_mouse() void = {
	mouse_poll();
	const dx = mouse_dx();
	const dy = mouse_dy();
	const b = mouse_buttons();
	if (dx != 0 || dy != 0 || b != lastbtn) {
		kit::mouse(dx, dy, b);
		lastbtn = b;
	};
	kit::sync();
};

// Returns one byte, or zero when nothing is waiting.
export fn pollch() u8 = {
	poll_mouse();
	if (serial_has_data()) {
		return serial_getc();
	};
	if (keyboard_has_data()) {
		return keyboard_getc();
	};
	return 0;
};

@init fn init() void = {
	serial_init();
	vga_init();
	mouse_init();
	rt::con_write = &write;
};
