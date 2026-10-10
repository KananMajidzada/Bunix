use arch;

def MEM: uintptr = 0xB8000;
def COLS: size = 80;
def ROWS: size = 25;

// Black on white: attribute 0x70 is a black foreground on VGA color 7, which
// the PAL here brightens from gray to white.
def ATTR: u16 = 0x7000;

let row: size = 0;
let col: size = 0;

fn cell(y: size, x: size) *u16 = {
	return (MEM + 2 * (y * COLS + x): uintptr): *u16;
};

export fn vga_init() void = {
	// VGA palette entry 7 is light gray by default. Brighten it to white so
	// the background reads as white rather than the usual gray.
	arch::outb(0x3C8, 7);
	arch::outb(0x3C9, 0x3F);
	arch::outb(0x3C9, 0x3F);
	arch::outb(0x3C9, 0x3F);
	vga_clear();
};

export fn vga_clear() void = {
	for (let y = 0z; y < ROWS; y += 1) {
		for (let x = 0z; x < COLS; x += 1) {
			*cell(y, x) = ATTR | (' ': u16);
		};
	};
	row = 0;
	col = 0;
	sync_cursor();
};

export fn vga_putc(ch: u8) void = {
	if (ch == '\n': u8) {
		row += 1;
		col = 0;
	} else if (ch == '\r': u8) {
		col = 0;
	} else {
		*cell(row, col) = ATTR | (ch: u16);
		col += 1;
	};
	if (col >= COLS) {
		col = 0;
		row += 1;
	};
	if (row >= ROWS) {
		scroll();
	};
	sync_cursor();
};

fn scroll() void = {
	for (let y = 1z; y < ROWS; y += 1) {
		for (let x = 0z; x < COLS; x += 1) {
			*cell(y - 1, x) = *cell(y, x);
		};
	};
	for (let x = 0z; x < COLS; x += 1) {
		*cell(ROWS - 1, x) = ATTR | (' ': u16);
	};
	row = ROWS - 1;
};

fn sync_cursor() void = {
	const pos = row * COLS + col;
	arch::outb(0x3D4, 0x0F);
	arch::outb(0x3D5, (pos & 0xFF): u8);
	arch::outb(0x3D4, 0x0E);
	arch::outb(0x3D5, ((pos >> 8) & 0xFF): u8);
};
