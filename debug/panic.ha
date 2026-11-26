use architecture;
use fb;
use rt;
use sound;

// The panic screen.
//
// A bad address in a program is somebody else's problem: that program is
// killed and the desktop goes on. But when the kernel itself has no safe way
// forward, it stops and says why on a plain white screen, with enough detail
// to work out where it went wrong.
//
// This runs with interrupts off and a stack that may not be trustworthy. It
// allocates nothing and uses only the framebuffer's own shadow buffer, which
// was mapped at boot.

def WHITE: u32 = 0xFFFFFF;
def BLACK: u32 = 0x000000;
def X: size = 24;
def STEP: size = 20;

// The two shell commands arrive through the fault handler too, so that both
// screens show a real register dump. Their words are kept here; on an
// ordinary boot the defaults say "Fault" and "kernel fault".
let heading: str = "Fault";
let why: str = "kernel fault";

// Set the words for a deliberate fault before causing it.
export fn describe(what: str, reason: str) void = {
	heading = what;
	why = reason;
};

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

// Sixteen hex digits, newest nibble last.
fn hex(buf: []u8, v: u64) size = {
	let n = 0z;
	for (let i = 0z; i < 16; i += 1) {
		const shift = ((15 - i) * 4): u64;
		const d = ((v >> shift) & 0xF): u8;
		buf[n] = if (d < 10) ('0': u8) + d else ('a': u8) + (d - 10);
		n += 1;
	};
	return n;
};

let y: size = X;

// One line, on the screen and on the serial port.
fn row(s: str) void = {
	if (fb::active()) {
		fb::text(X, y, s, BLACK, WHITE);
	};
	y += STEP;
	say(s);
};

// A label padded into a column, then a hex value.
fn valued(label: str, v: u64) void = {
	let buf: [80]u8 = [0...];
	let n = copy(buf[..], label);
	for (n < 10) {
		buf[n] = (' ': u8);
		n += 1;
	};
	buf[n] = ('0': u8);
	buf[n + 1] = ('x': u8);
	n += 2;
	n += hex(buf[n..], v);
	row(*(&buf[..n]: *str));
};

fn show(title: str, reason: str, regs: nullable *architecture::registers) never = {
	// No interrupts, no sound, no scheduler: nothing can run behind the
	// message or change what it says.
	architecture::cli();
	sound::audio_stop();

	if (fb::active()) {
		fb::fill(0, 0, fb::width(), fb::height(), WHITE);
	};

	y = X;
	say("");
	row(title);
	row("");

	let line: [160]u8 = [0...];
	let n = copy(line[..], "reason: ");
	n += copy(line[n..], reason);
	row(*(&line[..n]: *str));
	row("The kernel stopped. Reboot to start again.");
	row("");

	match (regs) {
	case null => void;
	case let f: *architecture::registers =>
		valued("vector", f.vector);
		valued("error", f.error);
		valued("cs", f.cs);
		valued("rflags", f.rflags);
		row("");
		valued("rip", f.rip);
		valued("rsp", f.rsp);
		valued("rbp", f.rbp);
		valued("rax", f.rax);
		valued("rbx", f.rbx);
		valued("rcx", f.rcx);
		valued("rdx", f.rdx);
		valued("rsi", f.rsi);
		valued("rdi", f.rdi);
		valued("r8", f.r8);
		valued("r9", f.r9);
		valued("r10", f.r10);
		valued("r11", f.r11);
		valued("r12", f.r12);
		valued("r13", f.r13);
		valued("r14", f.r14);
		valued("r15", f.r15);
		valued("cr2", architecture::fault_address());
		row("");
	};
	row("No process is running. Turn the machine off, or reset it.");

	if (fb::active()) {
		fb::present();
	};
	rt::halt();
};

// An unhandled fault, with the title and reason set for a deliberate shell
// command or the defaults when the machine got here on its own.
export fn fault(regs: *architecture::registers) never = {
	show(heading, why, regs);
};

// A panic with no register frame: the boot failed before there was one.
export fn panic(reason: str) never = {
	show("Kernel Panic", reason, null);
};
