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
// the terminal window uses. It is deliberately a handful of lines and not a
// transcript: the transcript is the serial line, and this is for the person
// standing in front of the machine.

def FG: u32 = 0xD0D0D0;
def DIM: u32 = 0x707070;
def BG: u32 = 0x101018;
def ACCENT: u32 = 0x69C8FF;

let started = false;
let row = 0z;

// The left margin, in cells. The text is put in from the edge rather than
// centred, because the lines change length as it fills in and a centred
// block would shuffle sideways while it did.
def MARGIN: size = 6;

fn row_y(n: size) size = {
	return 80 + n * (fb::CH + 4);
};

// Wipes the screen and writes the lines that do not change. Called as soon as
// there are pixels to draw on, which is before the window manager exists and
// so before there is any other place for this to go.
export fn begin() void = {
	if (!fb::active()) {
		return;
	};
	started = true;
	row = 0;
	fb::fill(0, 0, fb::width(), fb::height(), BG);
	fb::text_big(MARGIN * fb::CW, 24, "Bunix", 2, ACCENT, BG);
	fb::text((MARGIN + 1) * fb::CW, 70,
		"starting up, one moment", DIM, BG);
	fb::present();
};

// One line of progress, added as each stage of the boot finishes, so what is
// on the screen is the stages that are done rather than the one in progress.
export fn step(label: str) void = {
	if (!started) {
		return;
	};
	const x = MARGIN * fb::CW;
	const y = row_y(row);
	fb::text(x, y, "  ok  ", ACCENT, BG);
	fb::text(x + 6 * fb::CW, y, label, FG, BG);
	fb::present_rect(x, y, fb::width() - x, fb::CH);
	row += 1;
};

// A last line other than the list of stages, for the two things that end the
// screen: the note that the machine is ready, and any refusal that stops the
// boot where it stopped.
export fn note(label: str, warning: bool) void = {
	if (!started) {
		return;
	};
	const x = MARGIN * fb::CW;
	const y = row_y(row + 1);
	if (warning) {
		fb::text(x, y, label, 0xFF8080, BG);
	} else {
		fb::text(x, y, label, DIM, BG);
	};
	fb::present_rect(x, y, fb::width() - x, fb::CH);
};
