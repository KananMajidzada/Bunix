use architecture;
use fb;

// A boot screen: the kernel's boot log drawn onto the framebuffer.
//
// The serial port carries the full transcript for headless machines.
// Here we mirror the same lines onto the framebuffer so a person at
// the monitor sees what's happening. It's a simple scrolling text log
// in the same font the terminal uses. No graphics, no emojis, just
// the boot log.

def FG: u32 = 0x000000;  // black text
def DIM: u32 = 0x404040;  // dark gray text
def BG: u32 = 0xFFFFFF;  // white background
def ACCENT: u32 = 0x0000FF;  // blue accent

let started = false;
let log_lines: [24]str = [""...];
let log_count = 0z;

def MARGIN: size = 4;
def MAX_ROWS: size = 20;

fn row_y(n: size) size = {
	return 40 + n * (fb::CH + 2);
};

fn push_line(text: str) void = {
	if (log_count < 24) {
		log_lines[log_count] = text;
		log_count += 1;
	};
};

fn redraw_all() void = {
	const start: size = if (log_count > MAX_ROWS) log_count - MAX_ROWS else 0;
	for (let i = start; i < log_count; i += 1) {
		const y = row_y(i - start);
		fb::text(MARGIN * fb::CW, y, log_lines[i], FG, BG);
	};
	fb::present();
};

fn add_log(text: str) void = {
	if (log_count < 24) {
		log_lines[log_count] = text;
		log_count += 1;
	};
	redraw_all();
};

// Wipes the screen and writes the kernel name.
export fn begin() void = {
	if (!fb::active()) {
		return;
	};
	started = true;
	log_count = 0;
	fb::fill(0, 0, fb::width(), fb::height(), BG);
	fb::text_big(MARGIN * fb::CW, 12, "Bunix", 2, ACCENT, BG);
	redraw_all();
};

// Adds a line to the scrolling boot log.
export fn log(label: str) void = {
	if (!started) {
		return;
	};
	add_log(label);
	sleep_ms(300);  // pause so user can read each line
};

// A final note (warning or info) at the bottom.
export fn note(label: str, warning: bool) void = {
	if (!started) {
		return;
	};
	const x = MARGIN * fb::CW;
	const y = row_y(21);
	if (warning) {
		fb::text(x, y, label, 0xFF8080, BG);
	} else {
		fb::text(x, y, label, DIM, BG);
	};
	fb::present_rect(x, y, fb::width() - x, fb::CH);
};

// Small delay so each boot line is visible for a moment.
// Uses a simple busy-wait loop (doesn't rely on timer interrupt).
fn sleep_ms(ms: u64) void = {
	// Simple busy-wait delay (approximate, doesn't rely on timer interrupt)
	// At ~2-3 GHz, this gives roughly the right order of magnitude
	const iterations = (ms * 100000): size;
	for (let i = 0z; i < iterations; i += 1) {
		architecture::pause();
	};
};