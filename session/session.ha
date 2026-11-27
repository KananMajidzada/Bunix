// Opaque session routing for the kernel.
//
// The kernel keeps no idea of a window, a desktop, or a focus policy here. A
// session is just a number that a compositor gives to a group of threads. The
// kernel tags console output with the running thread's session, and hands
// keyboard input to the session the compositor says is current. The userland
// window manager decides what that number means; another one can use the same
// files with its own idea of a window.

@symbol("sched.bind_shell") fn sched_bind(id: size, ses: size) void;
@symbol("sched.set_spawn_ses") fn sched_set_spawn(wi: size) void;

def MAXOUT: size = 8192;

let out: [MAXOUT]u8 = [0...];
let outhead: size = 0;
let outtail: size = 0;
let outcount: size = 0;

let focused: size = 0;
let targetses: size = ~0z;

// The session a byte written now belongs to. The scheduler sets this on every
// thread switch; before it has, output goes to the focused session.
export fn target() size = {
	if (targetses != ~0z) {
		return targetses;
	};
	return focused;
};

export fn focus() size = return focused;
export fn set_focus(ses: size) void = focused = ses;
export fn set_target(ses: size) void = targetses = ses;

// The session the compositor wants the next program to start in. It has to be
// set before the program is spawned: the scheduler gives a thread its session
// as it enters, and a shell's first words are printed immediately after that.
export fn set_spawn(ses: size) void = sched_set_spawn(ses);

// A byte of console output, tagged with the session it came from. Two bytes
// per character: the session number, then the byte.
export fn putc(ch: u8, ses: size) void = {
	if (outcount + 2 > len(out)) {
		return;
	};
	out[outtail] = ses: u8;
	outtail = (outtail + 1) % MAXOUT;
	out[outtail] = ch;
	outtail = (outtail + 1) % MAXOUT;
	outcount += 2;
};

// /dev/sessionout: the stream of tagged bytes for a compositor to interpret.
export fn out_read(buf: []u8, off: u64, n: size) size = {
	_ = off;
	let k = 0z;
	for (k < n && k < len(buf) && outcount > 0) {
		buf[k] = out[outhead];
		outhead = (outhead + 1) % MAXOUT;
		outcount -= 1;
		k += 1;
	};
	return k;
};

// A freshly opened terminal session asks its shell to print a prompt.
let fresh = false;

export fn set_fresh() void = fresh = true;

export fn take_fresh() bool = {
	const was = fresh;
	fresh = false;
	return was;
};

// When a thread ends, a compositor may need to take back whatever it made for
// that thread. The kernel only reports the two opaque numbers it knows: the
// thread and the session it had. It says nothing about windows.
def MAXEXIT: size = 64;
let exitbuf: [MAXEXIT]u8 = [0...];
let exith: size = 0;
let exitt: size = 0;
let exitn: size = 0;

export fn exited(id: size, ses: size) void = {
	if (exitn + 2 > len(exitbuf)) {
		return;
	};
	exitbuf[exitt] = id: u8;
	exitt = (exitt + 1) % MAXEXIT;
	exitbuf[exitt] = ses: u8;
	exitt = (exitt + 1) % MAXEXIT;
	exitn += 2;
};

// /dev/sessionexit: pairs of thread number and session number, for whoever is
// managing the surfaces those numbers were used for.
export fn exit_read(buf: []u8, off: u64, n: size) size = {
	_ = off;
	let k = 0z;
	for (k < n && k < len(buf) && exitn > 0) {
		buf[k] = exitbuf[exith];
		exith = (exith + 1) % MAXEXIT;
		exitn -= 1;
		k += 1;
	};
	return k;
};

// The compositor spawns a shell for a new session and tells the kernel which
// session it belongs to, so keystrokes reach the right one. This is a binding
// of a thread to an opaque number, not a window operation.
export fn bind(data: []u8, off: u64) size = {
	_ = off;
	if (len(data) < 2) {
		return 0;
	};
	sched_bind(data[0]: size, data[1]: size);
	return len(data);
};
