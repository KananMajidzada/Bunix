use arch;

// Scan code set 1. Non-printing keys map to zero.
const unshifted: [128]u8 = [
	0,    0x1B, '1',  '2',  '3',  '4',  '5',  '6',
	'7',  '8',  '9',  '0',  '-',  '=',  '\b', '\t',
	'q',  'w',  'e',  'r',  't',  'y',  'u',  'i',
	'o',  'p',  '[',  ']',  '\n', 0,    'a',  's',
	'd',  'f',  'g',  'h',  'j',  'k',  'l',  ';',
	'\'', '`',  0,    '\\', 'z',  'x',  'c',  'v',
	'b',  'n',  'm',  ',',  '.',  '/',  0,    '*',
	0,    ' ',  0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
];

const shifted: [128]u8 = [
	0,    0x1B, '!',  '@',  '#',  '$',  '%',  '^',
	'&',  '*',  '(',  ')',  '_',  '+',  '\b', '\t',
	'Q',  'W',  'E',  'R',  'T',  'Y',  'U',  'I',
	'O',  'P',  '{',  '}',  '\n', 0,    'A',  'S',
	'D',  'F',  'G',  'H',  'J',  'K',  'L',  ':',
	'"',  '~',  0,    '|',  'Z',  'X',  'C',  'V',
	'B',  'N',  'M',  '<',  '>',  '?',  0,    '*',
	0,    ' ',  0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
	0,    0,    0,    0,    0,    0,    0,    0,
];

let shift = false;
let ctrl = false;

// Scancode set 1. The four cursor keys are E0-prefixed like the navigation
// keys, so they arrive as E0 48, E0 50, E0 4D and E0 4B. Home, End, the paging
// keys, Insert and Delete are E0 47, 4F, 49, 51, 52 and 53. Releasing an
// extended key sends the same code with bit 7 set.

// The cursor and editing keys do not fit in one byte, so they go out as the
// escape sequences a terminal expects. This queue holds the bytes of a sequence
// until the reader has taken them all.
def SEQ: size = 24;
let q: [SEQ]u8 = [0...];
let qhead: size = 0;
let qtail: size = 0;
let qn: size = 0;
// Set by the E0 that prefixes the second scancode of an extended key.
let ext = false;

fn qput(b: u8) void = {
	if (qn == SEQ) {
		return;
	};
	q[qtail] = b;
	qtail = (qtail + 1) % SEQ;
	qn += 1;
};

// CSI <final>, as the arrow keys use.
fn csi(final: int) void = {
	qput(0x1B);
	qput(0x5B);
	qput(final: u8);
};

// CSI <digit> ~, as the navigation keys use. The digit has to go out as its
// character, not as its value: CSI followed by a raw 1 is not something a
// reader can tell from a control code, so the tilde after it would arrive as a
// stray character of its own.
fn csi_tilde(digit: int) void = {
	qput(0x1B);
	qput(0x5B);
	qput(('0': u8) + (digit: u8));
	qput(0x7E);
};

// The controller holds a single byte and drops the next one if it is not read
// before the following key arrives. Reading it only when a program asks for
// input therefore loses keys whenever typing outruns the program, which is
// exactly what happens while a full-screen program is drawing. The interrupt
// takes each scancode the moment it lands and puts it here instead, so nothing
// is lost however slowly the reader gets round to it.
def RAW: size = 64;
let raw: [RAW]u8 = [0...];
let rawhead: size = 0;
let rawtail: size = 0;
let rawn: size = 0;

// Takes one scancode from the controller, or zero when there is nothing there.
// The interrupt uses this, and a program uses it directly as a fallback for the
// moments when interrupts are masked and no scancode could arrive otherwise.
fn take() u8 = {
	if (rawn > 0) {
		const sc = raw[rawhead];
		rawhead = (rawhead + 1) % RAW;
		rawn -= 1;
		return sc;
	};
	const st = arch::inb(0x64);
	if ((st & 1) == 0 || (st & 0x20) != 0) {
		return 0;
	};
	return arch::inb(0x60);
};

// Waits for the controller to take a byte, so setup does not race it.
fn kb_wait_write() void = {
	for (let i = 0; i < 100000; i += 1) {
		if ((arch::inb(0x64) & 2) == 0) {
			return;
		};
	};
};

// Waits for a byte to arrive, for the commands that return one.
fn kb_wait_read() void = {
	for (let i = 0; i < 100000; i += 1) {
		if ((arch::inb(0x64) & 1) != 0) {
			return;
		};
	};
};

// Puts the controller into a known state with the keyboard interrupt on.
// Nothing has set it up before, since the bootloader leaves it as it found the
// hardware, and a controller with interrupts off would leave the ring buffer
// empty however it was read.
export fn keyboard_init() void = {
	kb_wait_write();
	arch::outb(0x64, 0xAE);			// enable the keyboard port
	// Drain anything the controller is holding so no stale byte is taken for
	// a keystroke later on.
	for (let i = 0; i < 16; i += 1) {
		if ((arch::inb(0x64) & 1) == 0) {
			break;
		};
		_ = arch::inb(0x60);
	};
	kb_wait_write();
	arch::outb(0x64, 0x20);			// ask for the configuration byte
	kb_wait_read();
	const cfg = arch::inb(0x60);
	// Bit 0 off asks the controller to raise an interrupt for each key.
	kb_wait_write();
	arch::outb(0x64, 0x60);			// this is the configuration byte
	kb_wait_write();
	arch::outb(0x60, cfg & 0xFE);
};

// Called from the keyboard interrupt.
export fn keyboard_irq() void = {
	const sc = take();
	if (sc == 0) {
		return;
	};
	if (rawn == RAW) {
		// The reader has fallen a very long way behind. Dropping the
		// oldest is better than losing the newest, which is what the
		// controller would do on its own.
		rawhead = (rawhead + 1) % RAW;
		rawn -= 1;
	};
	raw[rawtail] = sc;
	rawtail = (rawtail + 1) % RAW;
	rawn += 1;
};

export fn keyboard_has_data() bool = {
	if (qn > 0 || rawn > 0) {
		return true;
	};
	// The interrupt normally fills the ring, but it is masked while a
	// program runs with interrupts off and is not wired up until the console
	// is set up, so the controller is still asked directly.
	const st = arch::inb(0x64);
	return (st & 1) != 0 && (st & 0x20) == 0;
};

// Turns one scancode into whatever bytes it means: an escape sequence for the
// arrow and navigation keys, a character for a key that types one, and nothing
// at all for a key that is only a modifier.
fn feed(sc: u8) void = {
	if (sc == 0x2A || sc == 0x36) {
		shift = true;
		return;
	};
	if (sc == 0xAA || sc == 0xB6) {
		shift = false;
		return;
	};
	// Left Ctrl is scancode 1D and its release carries bit 7. The right one
	// arrives as E0 1D. Alt is 38 on the left and E0 38 on the right.
	if (sc == 0x1D) {
		ctrl = true;
		return;
	};
	if (sc == 0x9D) {
		ctrl = false;
		return;
	};
	if (sc == 0x38) {
		return;
	};
	if (sc == 0xE0) {
		ext = true;
		return;
	};
	const was_ext = ext;
	ext = false;
	if (was_ext) {
		// The cursor keys, then the navigation keys, then the keypad.
		if (sc == 0x48) {
			csi(0x41);                 // Up
		} else if (sc == 0x50) {
			csi(0x42);                 // Down
		} else if (sc == 0x4D) {
			csi(0x43);                 // Right
		} else if (sc == 0x4B) {
			csi(0x44);                 // Left
		} else if (sc == 0x47) {
			csi_tilde(1);              // Home
		} else if (sc == 0x49) {
			csi_tilde(5);              // Page Up
		} else if (sc == 0x4F) {
			csi_tilde(4);              // End
		} else if (sc == 0x51) {
			csi_tilde(6);              // Page Down
		} else if (sc == 0x52) {
			csi_tilde(2);              // Insert
		} else if (sc == 0x53) {
			csi_tilde(3);              // Delete
		} else if (sc == 0x1D) {
			ctrl = true;               // E0 1D is the right Ctrl
		} else if (sc == 0x9D) {
			ctrl = false;
		} else if (sc == 0x38) {
			return;                    // E0 38 is the right Alt
		} else if (sc == 0x5B) {
			csi_tilde(1);              // keypad Home
		} else if (sc == 0x5C) {
			csi_tilde(4);              // keypad End
		};
		return;
	};
	if ((sc & 0x80) != 0) {
		return;
	};
	const ch = if (shift) shifted[sc: size] else unshifted[sc: size];
	// Ctrl with a letter gives the letter's control code, which is what every
	// program expects: Ctrl-C is 3, Ctrl-S is 19, Ctrl-X is 24.
	if (ctrl && ch >= ('a': u8) && ch <= ('z': u8)) {
		qput(ch & 0x1F);
		return;
	};
	if (ctrl && ch >= ('A': u8) && ch <= ('Z': u8)) {
		qput(ch & 0x1F);
		return;
	};
	qput(ch);
};

export fn keyboard_getc() u8 = {
	// Bytes already made from earlier scancodes come out first, so an escape
	// sequence is never split by a key that follows it.
	for (true) {
		if (qn > 0) {
			const b = q[qhead];
			qn -= 1;
			qhead = (qhead + 1) % SEQ;
			return b;
		};
		const sc = take();
		if (sc == 0) {
			return 0;
		};
		feed(sc);
	};
};
