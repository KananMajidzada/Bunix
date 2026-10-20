use fb;

// A boot screen, drawn straight onto the framebuffer.
//
// Everything the kernel says during boot also goes to the serial port, which
// is how a machine without a screen is watched. On a machine with one, the
// serial line goes nowhere and the text console has nothing to write into:
// the bootloader asked the card for a graphics mode, so there are no text
// cells left to print to, and the window manager that would draw them has not
// started yet. Without this the screen stays black from the mode switch until
// the first window appears, which on a slow disk is several seconds of no
// sign that anything is happening.
//
// So the first lines are drawn here instead, on the pixels, in the same font
// the terminal window uses. It's a scrolling text log with bunny-themed
// messages because why not.

def FG: u32 = 0xD0D0D0;
def DIM: u32 = 0x707070;
def BG: u32 = 0x101018;
def ACCENT: u32 = 0x69C8FF;
def EAR: u32 = 0xFFB6C1;

let started = false;
let row = 0z;
let log_lines: [20]str = [""...];
let log_count = 0z;

def MARGIN: size = 4;
def MAX_ROWS: size = 18;

fn row_y(n: size) size = {
	return 60 + n * (fb::CH + 2);
};

fn push_line(text: str) void = {
	if (log_count < 20) {
		log_lines[log_count] = text;
		log_count += 1;
	};
};

fn redraw_all() void = {
	let start: size = if (log_count > MAX_ROWS) log_count - MAX_ROWS else 0;
	for (let i = start; i < log_count; i += 1) {
		const y = row_y(i - start);
		fb::text(MARGIN * fb::CW, y, log_lines[i], FG, BG);
	};
	fb::present();
};

fn add_log(text: str) void = {
	push_line(text);
	redraw_all();
};

// Wipes the screen and writes the title. Called as soon as there are pixels.
export fn begin() void = {
	if (!fb::active()) {
		return;
	};
	started = true;
	row = 0;
	log_count = 0;
	fb::fill(0, 0, fb::width(), fb::height(), BG);
	fb::text_big(MARGIN * fb::CW, 12, "Bunix", 2, ACCENT, BG);
	// cute ears
	fb::text_big((MARGIN + 7) * fb::CW, 12, "🐰", 2, EAR, BG);
	redraw_all();
};

// Adds a bunny-themed log line to the scrolling text log.
export fn log(label: str) void = {
	if (!started) {
		return;
	};
	add_log(label);
};

// A final note (warning or info) at the bottom.
export fn note(label: str, warning: bool) void = {
	if (!started) {
		return;
	};
	const x = MARGIN * fb::CW;
	const y = row_y(MAX_ROWS);
	if (warning) {
		fb::text(x, y, label, 0xFF8080, BG);
	} else {
		fb::text(x, y, label, DIM, BG);
	};
	fb::present_rect(x, y, fb::width() - x, fb::CH);
};