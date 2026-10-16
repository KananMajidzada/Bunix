use architecture;

def MEM: uintptr = 0xB8000;
def COLS: size = 80;
def ROWS: size = 25;

def ATTR: u16 = 0x7000;

let row: size = 0;
let col: size = 0;

fn cell(y: size, x: size) *u16 = {
	return (MEM + 2 * (y * COLS + x): uintptr): *u16;
};

export fn vga_init() void = {
	architecture::outb(0x3C8, 7);
	architecture::outb(0x3C9, 0x3F);
	architecture::outb(0x3C9, 0x3F);
	architecture::outb(0x3C9, 0x3F);
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

// The size of the console, so a program can lay itself out to fit.
export fn vga_rows() size = return ROWS;

export fn vga_cols() size = return COLS;

// Blanks from the cursor to the end of the line.
fn erase_line_to_end() void = {
	for (let x = col; x < COLS; x += 1) {
		*cell(row, x) = ATTR | (' ': u16);
	};
};

// Blanks from the cursor to the end of the screen.
fn erase_display_to_end() void = {
	erase_line_to_end();
	for (let y = row + 1; y < ROWS; y += 1) {
		for (let x = 0z; x < COLS; x += 1) {
			*cell(y, x) = ATTR | (' ': u16);
		};
	};
};

fn move_cursor(r: size, c: size) void = {
	if (r < ROWS) {
		row = r;
	};
	if (c < COLS) {
		col = c;
	};
	sync_cursor();
};

// An escape sequence arrives one byte at a time and only means something once it
// is put back together. This is the whole of the terminal's control language:
// enough for a full-screen program to place the cursor and clear a line, which
// is what an editor needs to draw itself.
let state: int = 0;      // 0 plain text, 1 saw ESC, 2 collecting a CSI
let param: [16]u8 = [0...];
let nparam: size = 0;

fn handle_csi(final: u8) void = {
	let a = 0z;
	let b = 0z;
	let seen = 0;
	for (let i = 0z; i < nparam; i += 1) {
		const ch = param[i];
		if (ch == (';': u8)) {
			seen += 1;
			continue;
		};
		if (seen == 0) {
			a = a * 10 + (ch - ('0': u8));
		} else {
			b = b * 10 + (ch - ('0': u8));
		};
	};
	if (final == ('H': u8) || final == ('f': u8)) {
		// Cursor position, one based, and a missing number means one.
		move_cursor(if (a > 0) a - 1 else 0, if (b > 0) b - 1 else 0);
	} else if (final == ('J': u8)) {
		if (a == 2) {
			vga_clear();
		} else {
			erase_display_to_end();
		};
	} else if (final == ('K': u8)) {
		erase_line_to_end();
	} else if (final == ('A': u8)) {
		if (row > 0) {
			row -= 1;
			sync_cursor();
		};
	} else if (final == ('B': u8)) {
		if (row + 1 < ROWS) {
			row += 1;
			sync_cursor();
		};
	} else if (final == ('C': u8)) {
		if (col + 1 < COLS) {
			col += 1;
			sync_cursor();
		};
	} else if (final == ('D': u8)) {
		if (col > 0) {
			col -= 1;
			sync_cursor();
		};
	};
	// Anything else, colour and the like, is left alone.
};

export fn vga_putc(ch: u8) void = {
	if (state == 1) {
		state = 0;
		if (ch == ('[': u8)) {
			state = 2;
			nparam = 0;
		};
		return;
	};
	if (state == 2) {
		if ((ch >= ('0': u8) && ch <= ('9': u8)) || ch == (';': u8)) {
			if (nparam < len(param)) {
				param[nparam] = ch;
				nparam += 1;
			};
			return;
		};
		state = 0;
		handle_csi(ch);
		return;
	};
	if (ch == 0x1B) {
		state = 1;
		return;
	};
	if (ch == '\n': u8) {
		row += 1;
		col = 0;
	} else if (ch == '\r': u8) {
		col = 0;
	} else if (ch == '\b': u8) {
		if (col > 0) {
			col -= 1;
		} else if (row > 0) {
			row -= 1;
			col = COLS - 1;
		};
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
	architecture::outb(0x3D4, 0x0F);
	architecture::outb(0x3D5, (pos & 0xFF): u8);
	architecture::outb(0x3D4, 0x0E);
	architecture::outb(0x3D5, ((pos >> 8) & 0xFF): u8);
};
