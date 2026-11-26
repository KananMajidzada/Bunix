use architecture;
use fb;
use rt;
use sound;

// The panic screen.
//
// Ordinary faults have ordinary answers: a bad address in a program kills
// that program, and the desktop carries on. Some faults have no answer. The
// kernel has called the wrong thing, or a promise the machine was built on
// has broken, and there is no safe way to carry on. For those, the machine
// stops and says so where anybody can see it - on the screen, not only on a
// serial line somebody may not be watching.
//
// Everything here is prepared to run with interrupts off, possibly with a
// half-finished stack and a broken page table. It allocates nothing, follows
// no pointers but the register frame it is given, and uses only the
// framebuffer's own shadow buffer, which was mapped at boot.

def BG: u32 = 0x1A0000;       // dark red, the colour of a stopped machine
def BAR: u32 = 0xB00000;
def FG: u32 = 0xFFFFFF;
def DIM: u32 = 0xFFD9D9;
def X: size = 24;
def STEP: size = 24;

// Panic writes go straight to the serial port. Going through the console
// would also draw into the desktop terminal, on top of the panic picture.
fn say(s: str) void = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b); i += 1) {
		architecture::outb(0x3F8, b[i]);
	};
	architecture::outb(0x3F8, ('\n': u8));
};

// Sixteen hex digits, newest nibble last, into a caller's buffer.
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

fn copy(buf: []u8, s: str) size = {
	const b = *(&s: *[]u8);
	let n = 0z;
	for (let i = 0z; i < len(b) && n < len(buf); i += 1) {
		buf[n] = b[i];
		n += 1;
	};
	return n;
};

// One line on the screen and one on the serial line. The serial copy is for
// the person who booted the machine without a display; the screen copy is for
// whoever is sitting in front of it.
fn row(y: size, s: str, fg: u32) void = {
	if (fb::active()) {
		fb::text(X, y, s, fg, BG);
	};
	say(s);
};

// A label and a hex value, on one line.
fn valued(y: size, label: str, v: u64, fg: u32) void = {
	let buf: [80]u8 = [0...];
	let n = copy(buf[..], label);
	n += hex(buf[n..], v);
	row(y, *(&buf[..n]: *str), fg);
};

// Two registers on one line, one in each column.
fn pair(y: size, l: str, lv: u64, r: str, rv: u64, fg: u32) void = {
	let lb: [48]u8 = [0...];
	let ln = copy(lb[..], l);
	ln += hex(lb[ln..], lv);
	let rb: [48]u8 = [0...];
	let rn = copy(rb[..], r);
	rn += hex(rb[rn..], rv);
	if (fb::active()) {
		const half = (fb::width() / 2): size;
		fb::text(X, y, *(&lb[..ln]: *str), fg, BG);
		fb::text(half, y, *(&rb[..rn]: *str), fg, BG);
	};
	say(*(&lb[..ln]: *str));
	say(*(&rb[..rn]: *str));
};

fn show(reason: str, regs: nullable *architecture::registers) never = {
	// No interrupts, no sound, no scheduler: nothing that can run behind
	// the message and change what it says.
	architecture::cli();
	sound::audio_stop();

	say("");
	say("****************************************");
	say("BUNIX PANIC");
	say(reason);

	if (!fb::active()) {
		say("no framebuffer; the machine is stopped");
		rt::halt();
	};

	const w = fb::width();
	const h = fb::height();
	fb::fill(0, 0, w, h, BG);
	fb::fill(0, 0, w, 88, BAR);
	fb::text_big(X, 12, "BUNIX PANIC", 3, FG, BAR);

	let y = 104z;
	let r: [128]u8 = [0...];
	let n = copy(r[..], "reason: ");
	n += copy(r[n..], reason);
	row(y, *(&r[..n]: *str), FG);
	y += STEP;
	row(y, "The kernel stopped. Reboot to start again.", DIM);
	y += STEP * 2;

	match (regs) {
	case null => void;
	case let f: *architecture::registers =>
		let l: [80]u8 = [0...];
		let ln = copy(l[..], "vector 0x");
		ln += hex(l[ln..], f.vector);
		row(y, *(&l[..ln]: *str), FG);
		y += STEP;
		valued(y, "error   0x", f.error, FG);
		y += STEP;
		valued(y, "cs      0x", f.cs, FG);
		y += STEP;
		valued(y, "rflags  0x", f.rflags, FG);
		y += STEP * 2;

		pair(y, "rip 0x", f.rip, "rsp 0x", f.rsp, FG);
		y += STEP;
		pair(y, "rbp 0x", f.rbp, "rax 0x", f.rax, FG);
		y += STEP;
		pair(y, "rbx 0x", f.rbx, "rcx 0x", f.rcx, FG);
		y += STEP;
		pair(y, "rdx 0x", f.rdx, "rsi 0x", f.rsi, FG);
		y += STEP;
		pair(y, "rdi 0x", f.rdi, "r8  0x", f.r8, FG);
		y += STEP;
		pair(y, "r9  0x", f.r9, "r10 0x", f.r10, FG);
		y += STEP;
		pair(y, "r11 0x", f.r11, "r12 0x", f.r12, FG);
		y += STEP;
		pair(y, "r13 0x", f.r13, "r14 0x", f.r14, FG);
		y += STEP;
		pair(y, "r15 0x", f.r15, "cr2 0x", architecture::fault_address(), FG);
		y += STEP * 2;
	};

	if (y + STEP < h) {
		row(h - STEP - 8, "No process is running. Turn the machine off, or reset it.", DIM);
	};
	fb::present();
	rt::halt();
};

// A fault the CPU caught and nobody could handle.
export fn fault(reason: str, regs: *architecture::registers) never = {
	show(reason, regs);
};

// Somebody in the kernel found a mess that cannot be repaired.
export fn panic(reason: str) never = {
	show(reason, null);
};
