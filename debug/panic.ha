use architecture;
use fb;
use rt;
use sound;

// The panic screen.
//
// A bad address in a program is somebody else's problem: that program is
// killed and the desktop goes on. But when the kernel itself has no safe way
// forward, it stops and says why. No colours, no register tables, no noise -
// a white screen and the one thing worth knowing: the reason.
//
// This runs with interrupts off and a stack that may not be trustworthy. It
// allocates nothing and uses only the framebuffer's own shadow buffer, which
// was mapped at boot.

def WHITE: u32 = 0xFFFFFF;
def BLACK: u32 = 0x000000;
def X: size = 24;
def STEP: size = 28;

// Panic writes go straight to the serial port. Going through the console
// would draw into the desktop terminal, on top of the panic picture.
fn say(s: str) void = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b); i += 1) {
		architecture::outb(0x3F8, b[i]);
	};
	architecture::outb(0x3F8, ('\n': u8));
};

fn copy(buf: []u8, s: str) size = {
	const b = *(&s: *[]u8);
	let n = 0z;
	for (let i = 0z; i < len(b) && n < len(buf); i += 1) {
		buf[n] = b[i];
		n += 1;
	};
	return n;
};

fn show(reason: str) never = {
	// No interrupts, no sound, no scheduler: nothing can run behind the
	// message or change what it says.
	architecture::cli();
	sound::audio_stop();

	say("");
	say("BUNIX PANIC");
	say(reason);
	say("Reboot to start again.");

	if (!fb::active()) {
		rt::halt();
	};

	fb::fill(0, 0, fb::width(), fb::height(), WHITE);
	fb::text(X, X, "BUNIX PANIC", BLACK, WHITE);

	let line: [160]u8 = [0...];
	let n = copy(line[..], "reason: ");
	n += copy(line[n..], reason);
	fb::text(X, X + STEP * 2, *(&line[..n]: *str), BLACK, WHITE);
	fb::text(X, X + STEP * 3, "Reboot to start again.", BLACK, WHITE);

	fb::present();
	rt::halt();
};

// A fault the CPU caught and nobody could handle. The register frame is left
// to the serial log for anyone who wants it; the screen stays readable.
export fn fault(reason: str, regs: *architecture::registers) never = {
	_ = regs;
	show(reason);
};

// Somebody in the kernel found a mess that cannot be repaired.
export fn panic(reason: str) never = {
	show(reason);
};
