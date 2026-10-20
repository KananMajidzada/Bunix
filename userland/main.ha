use lib;
use rt;

// The programs /bin can hold. This is a cap and not a size: it has to be at
// least the number of entries in the kernel's program table, and a program
// past the end of it would be listed by /bin and completable but not runnable,
// which is the worst way for it to be wrong.
def MAXEXTPROG: size = 128;
def ARENASZ: size = 65536;
def SCRATCHSZ: size = 1024;

// Storage for unescaping a line and for rewriting a file to append to it.
let arena: [ARENASZ]u8 = [0...];
let scratch: [SCRATCHSZ]u8 = [0...];
def MAXNAME: size = 32;

// The listing of /bin comes back as one buffer of newline separated names.
// A name a program is given is matched against the whole of the table, so the
// table has to hold every program in the kernel and not just the first few.
def BINCAP: size = 2048;

let extprog_count: size = 0;
let extprog_names: [MAXEXTPROG][MAXNAME]u8 = [[0...]...];

fn load_bin() void = {
	let buf: [BINCAP]u8 = [0...];
	const n = rt::readdir("/bin", buf[..]);
	if (n == 0) {
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			const l = i - start;
			if (l > 0 && l < MAXNAME && extprog_count < MAXEXTPROG) {
				for (let j = 0z; j < l; j += 1) {
					extprog_names[extprog_count][j] = buf[start + j];
				};
				extprog_names[extprog_count][l] = 0;
				extprog_count += 1;
			};
			start = i + 1;
		};
	};
};

fn is_extprog(cmd: []u8) bool = {
	for (let i = 0z; i < extprog_count; i += 1) {
		let ok = true;
		for (let j = 0z; j < len(cmd); j += 1) {
			if (extprog_names[i][j] != cmd[j]) {
				ok = false;
				break;
			};
		};
		if (ok && extprog_names[i][len(cmd)] == 0) {
			return true;
		};
	};
	return false;
};

fn help_extprog() void = {
	for (let i = 0z; i < extprog_count; i += 1) {
		rt::print(" ");
		let j = 0z;
		for (extprog_names[i][j] != 0) {
			rt::putc(extprog_names[i][j]);
			j += 1;
		};
	};
	rt::println("");
};

// ---- the line editor ----
//
// The shell reads a line the way a terminal does: the cursor moves inside it,
// the arrows walk back through what has been typed, and tab fills in what can
// be finished. Every key arrives as a byte, with the cursor and navigation
// keys already put into the escape sequences a terminal expects, so decoding
// those below is the whole of the key handling.

def LINEMAX: size = 256;
def HISTMAX: size = 32;

let lb: [LINEMAX]u8 = [0...];
let n: size = 0;
// Where the cursor belongs in the line, and where the terminal was actually
// left. The two are not the same until the line is drawn again.
let cur: size = 0;
let shown: size = 0;

// Keys with no byte of their own. Nothing below 0x20 is taken, since those are
// the control codes, and nothing above 0x7F comes from the keyboard at all.
def KEY_UP: u8 = 0xF0;
def KEY_DOWN: u8 = 0xF1;
def KEY_RIGHT: u8 = 0xF2;
def KEY_LEFT: u8 = 0xF3;
def KEY_HOME: u8 = 0xF4;
def KEY_END: u8 = 0xF5;
def KEY_DEL: u8 = 0xF6;

let empty: []u8 = [];
let onebuf: [1]u8 = [0];

// Set by "exit", and looked at once the command has run. Leaving through the
// runtime's exit would take the whole process with it, and the shell has a
// path out of the loop of its own.
let quitting: bool = false;

// One byte if one is waiting, else zero. Not reading blocking is how the
// reader knows there is no second byte of an escape sequence to collect.
fn read_byte(blocking: bool) u8 = {
	for (let i = 0u64; true; i += 1) {
		const c = rt::readchr();
		if (c != 0) {
			return c;
		};
		if (!blocking) {
			return 0;
		};
		// Nothing typed yet. Give the rest of the system its turn rather than
		// standing on the only thread that can read the keyboard.
		rt::cop();
	};
};

// How many turns of the scheduler to wait for the rest of an escape sequence.
// The kernel hands a byte over a call after it reads it, so the bytes after an
// escape can still be on their way when the escape itself arrives. The wait is
// bounded: a bare Escape key then costs the turns it takes to give up, which
// is nothing, rather than hanging.
def TAILWAIT: u64 = 64;

fn tail_byte() u8 = {
	for (let i = 0u64; i < TAILWAIT; i += 1) {
		const c = rt::readchr();
		if (c != 0) {
			return c;
		};
		rt::cop();
	};
	return 0;
};

// Escape sequences arrive one byte at a time, so the escape is taken here and
// the bytes after it decide which key it was.
fn read_key() u8 = {
	const c = read_byte(true);
	if (c != 0x1B) {
		return c;
	};
	const a = tail_byte();
	if (a != ('[': u8)) {
		return 0x1B;
	};
	const b = tail_byte();
	// Home, End, Insert, Delete and the paging keys come as a digit and then
	// a tilde. The tilde has to be read and dropped or it lands in the line.
	if (b >= ('0': u8) && b <= ('9': u8)) {
		const t = tail_byte();
		if (t != ('~': u8)) {
			return 0x1B;
		};
		if (b == ('1': u8)) {
			return KEY_HOME;
		};
		if (b == ('4': u8)) {
			return KEY_END;
		};
		if (b == ('3': u8)) {
			return KEY_DEL;
		};
		if (b == ('5': u8)) {
			return KEY_UP;
		};
		if (b == ('6': u8)) {
			return KEY_DOWN;
		};
		return 0x1B;
	};
	if (b == 0x41) {
		return KEY_UP;
	};
	if (b == 0x42) {
		return KEY_DOWN;
	};
	if (b == 0x43) {
		return KEY_RIGHT;
	};
	if (b == 0x44) {
		return KEY_LEFT;
	};
	if (b == 0x48) {
		return KEY_HOME;
	};
	if (b == 0x46) {
		return KEY_END;
	};
	return 0x1B;
};

// Draws the line again and leaves the cursor where it was.
//
// Nothing echoes what is typed here: the kernel reads a key and hands it over
// without printing it, so this function is the only thing that ever puts a
// character on the screen after the prompt. That means the shell is the only
// thing that knows where the cursor is, and it has to keep a record of it.
//
// shown is that record: where the cursor actually is, counted from the start
// of the line. cur is where it should be. They differ because typing changes
// cur without moving anything on the screen, and it is shown that says how far
// to step back to reach the start of the line. Taking that from cur instead
// draws the line one place further left for every character typed, which walks
// it over the prompt and then off the side of the screen.
//
// Erasing to the end of the line rather than counting what was there before is
// what makes deleting a character in the middle come out right.
fn redraw() void = {
	for (let i = 0z; i < shown; i += 1) {
		rt::putc('\b': u8);
	};
	rt::write(lb[..n]);
	// Erasing to the end of the screen rather than to the end of the line is
	// what a line that has wrapped needs. A line longer than the console is
	// wide spills onto the next row, and shortening it leaves what was on
	// that row still sitting there unless the erase reaches it too.
	const e: str = "\x1b[J";
	rt::print(e);
	// The line has just been written whole, so the cursor is at its end; step
	// back over what comes after the one it belongs on.
	for (let i = 0z; i < n - cur; i += 1) {
		rt::putc('\b': u8);
	};
	shown = cur;
};

// Moves the cursor on the screen to match a move in the line. Used where the
// character under the cursor is already drawn and only the cursor has to
// follow, so there is no reason to draw the line again.
fn showcur() void = {
	for (let i = shown; i < cur; i += 1) {
		rt::putc(lb[i]);
	};
	for (let i = cur; i < shown; i += 1) {
		rt::putc('\b': u8);
	};
	shown = cur;
};

// Replaces the bytes from `at` to `to` with `text` and leaves the cursor after
// what was put there.
fn splice(at: size, to: size, text: []u8) void = {
	const tail = n - to;
	if (at + len(text) + tail > LINEMAX) {
		return;
	};
	// Which way round to move the tail depends on which way the gap has
	// moved. Closing a gap downwards writes each byte below where it came
	// from, so the copy has to run from the top or the next byte along reads
	// one that has already been moved. Opening one, as inserting does, is the
	// other way round and has to run from the back for the same reason.
	//
	// Getting this wrong is quiet: a delete then leaves the character after
	// the one removed duplicated, which looks like a shell that mangles text.
	if (at + len(text) <= to) {
		for (let i = 0z; i < tail; i += 1) {
			lb[at + len(text) + i] = lb[to + i];
		};
	} else {
		for (let i = tail; i > 0; i -= 1) {
			lb[at + len(text) + i - 1] = lb[to + i - 1];
		};
	};
	for (let i = 0z; i < len(text); i += 1) {
		lb[at + i] = text[i];
	};
	n = at + len(text) + tail;
	cur = at + len(text);
	redraw();
};

fn one(c: u8) []u8 = {
	onebuf[0] = c;
	return onebuf[..1];
};

// ---- history ----

let hist: [HISTMAX][LINEMAX]u8 = [[0...]...];
let hlen: [HISTMAX]size = [0...];
let hcount: size = 0;
// Where the arrows have got to. Equal to hcount means "the line being typed",
// which is where they start and where they come back to on the way down.
let hpos: size = 0;

fn remember() void = {
	if (n == 0) {
		return;
	};
	// A command typed twice in a row is one command as far as the arrows are
	// concerned.
	if (hcount > 0 && len(lb) == hlen[hcount - 1]
			&& lib::str_eq(lb[..n], hist[hcount - 1][..hlen[hcount - 1]])) {
		return;
	};
	if (hcount == HISTMAX) {
		// The oldest goes: a long session is worth more than the start of it.
		for (let i = 0z; i + 1 < HISTMAX; i += 1) {
			for (let j = 0z; j < hlen[i]; j += 1) {
				hist[i][j] = hist[i + 1][j];
			};
			hlen[i] = hlen[i + 1];
		};
		hcount -= 1;
	};
	for (let i = 0z; i < n; i += 1) {
		hist[hcount][i] = lb[i];
	};
	hlen[hcount] = n;
	hcount += 1;
};

fn setline(text: []u8) void = {
	n = 0z;
	for (let i = 0z; i < len(text) && i < LINEMAX; i += 1) {
		lb[n] = text[i];
		n += 1;
	};
	cur = n;
	redraw();
};

// Older sits at a larger index, so the arrows walk the table backwards.
fn older() void = {
	if (hpos == 0) {
		return;
	};
	hpos -= 1;
	setline(hist[hpos][..hlen[hpos]]);
};

fn newer() void = {
	if (hpos + 1 >= hcount) {
		hpos = hcount;
		setline(empty);
		return;
	};
	hpos += 1;
	setline(hist[hpos][..hlen[hpos]]);
};

// ---- tab completion ----

def MATCHCAP: size = 64;
def DIRCAP: size = 1024;

// Matches are held as addresses into cbin rather than copied out. Anything
// copied would have to live somewhere the recursion below does not reuse, and
// the listing they point into is already a buffer of the shell's own.
let matches: [MATCHCAP]uintptr = [0...];
let matchlen: [MATCHCAP]size = [0...];
let nmatches: size = 0;
let cbin: [DIRCAP]u8 = [0...];
let cbuf: [LINEMAX]u8 = [0...];

fn record(s: []u8) void = {
	if (nmatches < MATCHCAP) {
		matches[nmatches] = lib::at_ptr(s);
		matchlen[nmatches] = lib::at_len(s);
		nmatches += 1;
	};
};

fn record_ifb(typed: []u8, name: []u8) void = {
	if (lib::starts_with(name, typed)) {
		record(name);
	};
};

fn bindir() []u8 = {
	return *(&"/bin": *[]u8);
};

// The built-ins, as one line. Both help and tab completion read this rather
// than each keeping a copy, so a command is listed and completable the moment
// it is dispatched and cannot be left out of one of them by accident.
fn builtins() []u8 = {
	return *(&"cat cc clear echo exit false halt hd help history ls mkdir "
		"multi pwd reboot rm touch true tutorial user version write": *[]u8);
};

// The images the kernel has folded into /bin. The listing comes back as one
// name per line and a space is what a list of names is separated by
// everywhere else in this file, so the line ends are turned into spaces as it
// is copied across.
def CMDCAP: size = 1024;
let cmds: [CMDCAP]u8 = [0...];

fn bin_commands() []u8 = {
	const list = lib::listdir(bindir());
	let n = 0z;
	for (let i = 0z; i < len(list) && n < len(cmds); i += 1) {
		cmds[n] = if (list[i] == ('\n': u8)) ' ': u8 else list[i];
		n += 1;
	};
	return cmds[..n];
};

fn record_builtins(typed: []u8) void = {
	const names = builtins();
	let pos = 0z;
	for (let k = 0z; pos < len(names); k += 1) {
		let (name, next) = lib::next_arg(names, pos);
		pos = next;
		if (len(name) > 0) {
			record_ifb(typed, name);
		};
	};
	for (let i = 0z; i < extprog_count; i += 1) {
		let k = 0z;
		for (let j = 0z; j < MAXNAME && extprog_names[i][j] != 0; j += 1) {
			k += 1;
		};
		record_ifb(typed, extprog_names[i][..k]);
	};
};

// A path is completed against the directory it names. That is everything up to
// the last slash, or the root when there is none, because a process has no
// working directory to be anywhere else.
fn record_paths(dir: []u8, typed: []u8) void = {
	const n = rt::readdir(*(&dir: *str), cbin[..]);
	let at = 0z;
	for (let i = 0z; at < n; i += 1) {
		let (name, next) = lib::name_at(cbin[..n], at);
		at = next;
		if (len(name) == 0) {
			continue;
		};
		record_ifb(typed, name);
	};
};

// The word the cursor sits in, found by walking out from the cursor in both
// directions. It has to be walked backwards to find where the word begins: a
// line with no blanks in it at all has to come back as starting at zero, or
// tab completion takes the first word for an ordinary path and looks it up in
// the filesystem instead of among the commands.
fn word_at() (size, size) = {
	let start = cur;
	for (let i = cur; i > 0 && !lib::is_space(lb[i - 1]); i -= 1) {
		start = i - 1;
	};
	let end = cur;
	for (let i = cur; i < n && !lib::is_space(lb[i]); i += 1) {
		end = i + 1;
	};
	return (start, end);
};

// The longest run of bytes every match has at the front. When more than one
// name fits, filling in what all of them agree on is more use than either
// stopping short or picking one of them.
fn shared(with: []u8) size = {
	let k = len(with);
	for (let i = 0z; i < nmatches; i += 1) {
		const m = lib::view(matches[i], matchlen[i]);
		let j = 0z;
		for (let t = 0z; j < k && j < len(m) && with[j] == m[j]; j += 1) {
			t += 1;
		};
		k = j;
	};
	return k;
};

fn join_into(buf: []u8, a: []u8, b: []u8) size = {
	let k = 0z;
	for (let i = 0z; i < len(a) && k < len(buf); i += 1) {
		buf[k] = a[i];
		k += 1;
	};
	for (let i = 0z; i < len(b) && k < len(buf); i += 1) {
		buf[k] = b[i];
		k += 1;
	};
	return k;
};

fn match_at(i: size) []u8 = {
	return lib::view(matches[i], matchlen[i]);
};

fn complete() void = {
	let (start, end) = word_at();
	const typed = lb[start..end];
	nmatches = 0;
	// The first word names a command and only a command. Completing it
	// against the filesystem would bury the built-ins under every file that
	// happens to start the same way.
	if (start == 0) {
		record_builtins(typed);
		if (nmatches == 1) {
			splice(start, end, match_at(0));
			return;
		};
		if (nmatches > 1) {
			const k = shared(match_at(0));
			if (k > len(typed)) {
				splice(start, end, match_at(0)[..k]);
				return;
			};
			rt::println("");
			for (let i = 0z; i < nmatches; i += 1) {
				rt::println(*(&match_at(i): *str));
			};
			rt::print("ush> ");
			shown = 0z;
			redraw();
		};
		return;
	};

	// Everything up to the last slash is the directory, the rest is the part
	// to match on.
	let slash = 0z;
	for (let i = 0z; i < len(typed); i += 1) {
		if (typed[i] == ('/': u8)) {
			slash = i + 1;
		};
	};
	const dir = typed[..slash];
	const base = typed[slash..];
	record_paths(if (slash == 0) lib::root_dir() else dir, base);
	if (nmatches == 0) {
		return;
	};
	if (nmatches == 1) {
		const k = join_into(cbuf[..], dir, match_at(0));
		splice(start, end, cbuf[..k]);
		return;
	};
	const k = shared(match_at(0));
	if (k > len(base)) {
		const n2 = join_into(cbuf[..], dir, match_at(0)[..k]);
		splice(start, end, cbuf[..n2]);
		return;
	};
	rt::println("");
	for (let i = 0z; i < nmatches; i += 1) {
		rt::println(*(&match_at(i): *str));
	};
	rt::print("ush> ");
	shown = 0z;
	redraw();
};

// ---- help ----

// Prints a run of space separated words, breaking the line to fit the
// console. The two lists help prints are the only ones long enough to want it,
// and neither is worth a format of its own.
fn wraptxt(text: []u8) void = {
	let pos = 0z;
	let col = 0z;
	for (let k = 0z; pos < len(text); k += 1) {
		let (word, next) = lib::next_arg(text, pos);
		pos = next;
		if (len(word) == 0) {
			continue;
		};
		if (col > 0 && col + 1 + len(word) > WRAP) {
			rt::println("");
			col = 0;
		} else if (col > 0) {
			rt::putc(' ': u8);
			col += 1;
		};
		rt::write(word);
		col += len(word);
	};
	rt::println("");
};

// What this shell knows, as names and nothing else. A page of prose under
// every one of them is a page nobody reads, and a name says nearly as much as
// a sentence does. tutorial is where the explanations live.
fn print_help() void = {
	rt::println("built in:");
	wraptxt(builtins());
	rt::println("");
	rt::println("in /bin:");
	wraptxt(bin_commands());
};

fn show_history() void = {
	if (hcount == 0) {
		rt::println("nothing yet");
		return;
	};
	for (let i = 0z; i < hcount; i += 1) {
		rt::print("  ");
		rt::printnum((i + 1): u64);
		rt::println(*(&hist[i][..hlen[i]]: *str));
	};
};

// ---- tutorial ----
//
// What the system is and how to use it. Help is names only, so this is where
// somebody who has just booted it starts. The prose is wrapped in the source
// the way any other code is, which is what these two helpers are for.

def WRAP: size = 72;

let parabuf: [1024]u8 = [0...];
let paralen: size = 0;

fn say(rest: str) void = {
	const b = *(&rest: *[]u8);
	for (let i = 0z; i < len(b) && paralen < len(parabuf); i += 1) {
		parabuf[paralen] = b[i];
		paralen += 1;
	};
};

// Closes off the paragraph being built and prints it.
fn para() void = {
	wraptxt(parabuf[..paralen]);
	rt::println("");
	paralen = 0;
};

fn section(title: str) void = {
	rt::println("");
	rt::println(title);
	rt::println("");
};

fn tutorial() void = {
	section("Bunix");
	say("An operating system written in Hare. A kernel with paging, a ");
	say("scheduler, a filesystem and an ATAPI driver; a window manager on top; ");
	say("and a userland with a shell, a C compiler and an editor. help lists ");
	say("the commands and man explains one. This is what none of that says.");
	para();

	section("The two shells");
	say("ush> is the userland shell. Type a name and it runs /bin/<name>, or a ");
	say("path and it runs that. bunix> is the kernel shell, which needs no ");
	say("userland and is what answers if the userland will not start.");
	para();

	section("The filesystem");
	say("Everything hangs off /. /bin holds the programs. /usr has the C ");
	say("headers, the libraries and two examples. /tmp is scratch and is the ");
	say("only place you can write. /mnt is the disk once one is attached. /dev ");
	say("has cons, null, note and the raw disk, and /proc is built while you ");
	say("read it, one file per question.");
	para();

	section("Writing a program");
	say("tcc runs inside the kernel, so the system can build programs without ");
	say("leaving itself:");
	para();
	say("  write /tmp/h.c \"#include <stdio.h>\\nint main(void){puts(\"hi\");}\\n\"");
	para();
	say("  cc -o /tmp/h /tmp/h.c");
	para();
	say("  /tmp/h");
	para();

	section("The editor");
	say("mei takes the screen over. Arrows move, Ctrl-S saves, Ctrl-X saves and ");
	say("leaves, Ctrl-Q throws the changes away.");
	para();

	section("What is not here");
	say("No pipes, so a filter reads a file and never another command's output. ");
	say("No chdir: every process starts at / and pwd always says /.");
	para();
	say("Writing a file replaces it whole, which is why write -a reads it back ");
	say("and writes it again. A program started with user gets a filesystem of ");
	say("its own; one started by the shell shares the shell's.");
	para();
	say("There are two clocks and they disagree. The kernel timer counts from ");
	say("boot and is what scheduling and uptime use. The date comes from the ");
	say("clock on the motherboard, which is the only thing that knows what year ");
	say("it is, and which nothing checks.");
	para();

	section("Building it");
	say("make produces bunix.bin. Run it with make run, or with ");
	say("qemu-system-x86_64 -m 256 -kernel bunix.bin -serial stdio.");
	para();
};

fn vpath() []u8 = {
	return *(&"/proc/version": *[]u8);
};

fn slash() []u8 = {
	return *(&"/": *[]u8);
};

// Erases the screen and puts the cursor back at the top left. The console
// understands this the same as any terminal does.
fn clear_screen() void = {
	const e: str = "\x1b[2J\x1b[H";
	rt::print(e);
};

fn starts(s: str, p: str) bool = {
	const b = *(&s: *[]u8);
	const pb = *(&p: *[]u8);
	if (len(b) < len(pb)) {
		return false;
	};
	for (let i = 0z; i < len(pb); i += 1) {
		if (b[i] != pb[i]) {
			return false;
		};
	};
	return true;
};

// Run a program in an image of its own and wait for it. The loader picks the
// image by the first word of the line.
fn run(line: []u8) void = {
	const pid = rt::spawn_shared(*(&line: *str));
	if (pid == ~0u64) {
		rt::println("cannot run");
		return;
	};
	for (rt::alive(pid)) {
		rt::cop();
	};
};

fn report(ok: bool, yes: str, no: str) void = {
	if (ok) {
		rt::println(yes);
	} else {
		rt::println(no);
	};
};

// A command naming something in the filesystem rather than a built-in. The
// loader decides whether it is an executable to run or a file to read.
fn is_path(cmd: []u8) bool = {
	if (len(cmd) == 0 || cmd[0] != ('/': u8)) {
		return false;
	};
	return rt::exists(*(&cmd: *str));
};

// Splits a line into the command and the rest, the way every dispatch below
// wants it.
fn exec(line: []u8) void = {
	const sp = lib::first_space(line);
	const cmd = line[..sp];
	const rest = if (sp < len(line)) line[sp + 1..] else line[..0];

	if (lib::eq_str(cmd, "exit")) {
		rt::println("bye");
		quitting = true;
	} else if (lib::eq_str(cmd, "help")) {
		print_help();
	} else if (lib::eq_str(cmd, "tutorial")) {
		tutorial();
	} else if (lib::eq_str(cmd, "version")) {
		run_cat(vpath());
	} else if (lib::eq_str(cmd, "echo")) {
		rt::write(rest);
		rt::println("");
	} else if (lib::eq_str(cmd, "clear")) {
		clear_screen();
	} else if (lib::eq_str(cmd, "pwd")) {
		// Nothing to change directory in: every process starts at the root
		// and there is no chdir behind this, so this is always the answer.
		rt::println("/");
	} else if (lib::eq_str(cmd, "history")) {
		show_history();
	} else if (lib::eq_str(cmd, "true")) {
		void;
	} else if (lib::eq_str(cmd, "false")) {
		rt::println("false");
	} else if (lib::eq_str(cmd, "ls")) {
		const long = lib::starts_with(rest, *(&"-l": *[]u8));
		const path = if (long) lib::trim(rest[2..]) else rest;
		run_ls(if (len(path) == 0) slash() else path, long);
	} else if (lib::eq_str(cmd, "cat")) {
		run_cat(rest);
	} else if (lib::eq_str(cmd, "write")) {
		do_write(rest);
	} else if (lib::eq_str(cmd, "hd")) {
		run_hd(rest);
	} else if (lib::eq_str(cmd, "cc")) {
		run_cc(rest);
	} else if (lib::eq_str(cmd, "mkdir")) {
		report(rt::mkdir(*(&rest: *str)), "created", "cannot create");
	} else if (lib::eq_str(cmd, "touch")) {
		report(rt::create(*(&rest: *str)), "created", "cannot create");
	} else if (lib::eq_str(cmd, "rm")) {
		report(rt::remove(*(&rest: *str)), "removed", "cannot remove");
	} else if (is_extprog(cmd)) {
		// external program with an image of its own
		run(line);
	} else if (is_path(cmd)) {
		// a path into the filesystem: the loader decides whether it
		// is an executable to run or a file to read
		run(line);
	} else if (lib::eq_str(cmd, "user")) {
		do_user(rest);
	} else if (lib::eq_str(cmd, "multi")) {
		multi();
	} else if (lib::eq_str(cmd, "halt")) {
		rt::print("halting. ");
		rt::haltsys();
	} else if (lib::eq_str(cmd, "reboot")) {
		// Nothing comes back from this. The kernel waits for the serial line
		// to go quiet before pulling the reset line, so this message does
		// arrive rather than being lost in the port's FIFO.
		rt::print("rebooting.\n");
		rt::rebootsys();
	} else {
		rt::print("unknown command: ");
		rt::println(*(&cmd: *str));
	};
};

// Lists a directory. A directory has no contents to read as a file, so this
// goes through readdir instead. -l puts the size beside each name, which is
// what makes a listing worth reading when the directory is /usr/include.
fn run_ls(path: []u8, long: bool) void = {
	let buf: [1024]u8 = [0...];
	const n = rt::readdir(*(&path: *str), buf[..]);
	if (n == 0) {
		if (rt::isdir(*(&path: *str))) {
			// An empty directory says nothing at all through readdir, which is
			// worth saying plainly rather than just repeating the path.
			rt::println("(empty)");
			return;
		};
		rt::print("ls: nothing in ");
		rt::println(*(&path: *str));
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				const name = buf[start..i];
				if (long) {
					const joined = pathin(path, name);
					rt::printnum(rt::filesize(*(&jbuf[..joined]: *str)));
					rt::putc(' ': u8);
				};
				rt::write(name);
				rt::println("");
			};
			start = i + 1;
		};
	};
	void;
};

let jbuf: [512]u8 = [0...];

// A directory and a name put together into a whole path. ls -l needs this to
// ask about each entry, and it has to add the separator itself: a directory
// named in the command does not end with one.
fn pathin(dir: []u8, name: []u8) size = {
	let k = 0z;
	for (let i = 0z; i < len(dir) && k < len(jbuf); i += 1) {
		jbuf[k] = dir[i];
		k += 1;
	};
	if (k > 0 && jbuf[k - 1] != ('/': u8) && k < len(jbuf)) {
		jbuf[k] = '/': u8;
		k += 1;
	};
	for (let i = 0z; i < len(name) && k < len(jbuf); i += 1) {
		jbuf[k] = name[i];
		k += 1;
	};
	return k;
};

// Turns the escapes a person actually types at the shell into bytes. Without
// this, "write f "a\nb"" would store a backslash and an n.
fn unescape(src: []u8) []u8 = {
	let n = 0z;
	let i = 0z;
	for (i < len(src) && n < len(scratch); i += 1) {
		let c = src[i];
		if (c == ('\\': u8) && i + 1 < len(src)) {
			const e = src[i + 1];
			i += 1;
			if (e == ('n': u8)) {
				c = ('\n': u8);
			} else if (e == ('t': u8)) {
				c = ('\t': u8);
			} else if (e == ('r': u8)) {
				c = ('\r': u8);
			} else if (e == ('0': u8)) {
				c = 0;
			} else {
				c = e;
			};
		};
		scratch[n] = c;
		n += 1;
	};
	return scratch[..n];
};

// Append by rewriting: the filesystem's write always lands at offset zero, so
// the old bytes have to be carried along.
fn append_text(path: str, text: []u8) size = {
	const have = rt::readfile(path, arena[..]);
	let n = have;
	for (let i = 0z; i < len(text) && n < len(arena); i += 1) {
		arena[n] = text[i];
		n += 1;
	};
	return rt::writefile(path, arena[..n]);
};

// write [-a] <path> <text>
fn do_write(rest: []u8) void = {
	let body = rest;
	let do_append = false;
	if (len(body) >= 3 && body[0] == ('-': u8) && body[1] == ('a': u8)
			&& (body[2] == (' ': u8) || body[2] == ('\t': u8))) {
		do_append = true;
		body = body[3..];
		for (len(body) > 0 && (body[0] == (' ': u8) || body[0] == ('\t': u8))) {
			body = body[1..];
		};
	};
	const w = lib::first_space(body);
	if (w == len(body)) {
		rt::println("usage: write [-a] <path> <text>");
		return;
	};
	const path = body[..w];
	let raw = body[w + 1..];
	if (len(raw) >= 2) {
		const db = *(&raw: *[]u8);
		if ((db[0] == ('"': u8) && db[len(db) - 1] == ('"': u8))
				|| (db[0] == 39 && db[len(db) - 1] == 39)) {
			raw = raw[1..len(raw) - 1];
		};
	};
	const text = unescape(raw);
	let k = 0z;
	if (do_append) {
		k = append_text(*(&path: *str), text);
	} else {
		k = rt::writefile(*(&path: *str), text);
	};
	rt::print("wrote ");
	rt::printnum(k: u64);
	rt::println(" bytes");
};

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

// A hex dump, "hd <path> [offset]". Read through a heap window so it works on
// a file too large for a stack buffer, which is what a linked executable is.
fn run_hd(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: hd <path> [offset]");
		return;
	};
	const sp = lib::first_space(rest);
	const path = rest[..sp];
	let off = 0z;
	if (sp < len(rest)) {
		off = lib::parse_int(rest[sp + 1..], 0): size;
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("hd: out of memory");
		return;
	};
	const view = (window: *[65536]u8)[..];
	const n = rt::readfile(*(&path: *str), view);
	if (n == 0) {
		rt::println("no such file");
		return;
	};
	for (let i = off; i < n; i += 16) {
		rt::putc(hexdig((i >> 12): u8 & 0x0f));
		rt::putc(hexdig((i >> 8): u8 & 0x0f));
		rt::putc(hexdig((i >> 4): u8 & 0x0f));
		rt::putc(hexdig(i: u8 & 0x0f));
		rt::print(": ");
		for (let j = 0z; j < 16 && i + j < n; j += 1) {
			const b = view[i + j];
			rt::putc(hexdig(b >> 4));
			rt::putc(hexdig(b & 0x0f));
			rt::putc(' ': u8);
		};
		rt::println("");
	};
};

// Append one piece onto the end of a buffer.
fn put_into(out: []u8, at: *size, s: []u8) void = {
	for (let i = 0z; i < len(s) && *at < len(out); i += 1) {
		out[*at] = s[i];
		*at = *at + 1;
	};
};

// The command line for the compiler inside Bunix. tcc links against our own
// startup objects and library and must not go looking for a host system, so the
// flags are spelled out once here rather than at every prompt.
fn cc_line(args: []u8) void = {
	const head: str = "tcc ";
	const flags: str = "-static -nostdlib -B/usr/lib -L/usr/lib -I/usr/include";
	const crt1: str = " /usr/lib/crt1.o";
	const crti: str = " /usr/lib/crti.o";
	const libc: str = " /usr/lib/libc.a";
	const crtn: str = " /usr/lib/crtn.o";
	let buf: [600]u8 = [0...];
	let n = 0z;
	put_into(buf[..], &n, *(&head: *[]u8));
	put_into(buf[..], &n, *(&flags: *[]u8));
	put_into(buf[..], &n, args);
	put_into(buf[..], &n, *(&crt1: *[]u8));
	put_into(buf[..], &n, *(&crti: *[]u8));
	put_into(buf[..], &n, *(&libc: *[]u8));
	put_into(buf[..], &n, *(&crtn: *[]u8));
	run(buf[..n]);
};

// cc [-o out] source...  compiles and links against the Bunix runtime.
fn run_cc(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: cc [-o outfile] file.c ...");
		return;
	};
	const gap: str = " ";
	let outp: [256]u8 = [0...];
	let outn = 0z;
	let srcs: [400]u8 = [0...];
	let n = 0z;
	let i = 0z;
	for (true) {
		for (i < len(rest) && (rest[i] == (' ': u8) || rest[i] == ('\t': u8))) {
			i += 1;
		};
		const start = i;
		for (i < len(rest) && rest[i] != (' ': u8) && rest[i] != ('\t': u8)) {
			i += 1;
		};
		if (start == i) {
			break;
		};
		const tok = rest[start..i];
		if (len(tok) > 2 && tok[0] == ('-': u8) && (tok[1] == ('o': u8) || tok[1] == ('O': u8))) {
			const v = tok[2..];
			let k = len(v);
			if (k > len(outp)) {
				k = len(outp);
			};
			for (let j = 0z; j < k; j += 1) {
				outp[j] = v[j];
			};
			outn = k;
			continue;
		};
		put_into(srcs[..], &n, tok);
		put_into(srcs[..], &n, *(&gap: *[]u8));
	};
	if (n == 0) {
		rt::println("cc: no input files");
		return;
	};
	let args: [600]u8 = [0...];
	let an = 0z;
	const dasho: str = "-o ";
	put_into(args[..], &an, *(&dasho: *[]u8));
	put_into(args[..], &an, outp[..outn]);
	put_into(args[..], &an, *(&gap: *[]u8));
	put_into(args[..], &an, srcs[..n]);
	cc_line(args[..an]);
};

fn run_cat(path: []u8) void = {
	if (len(path) == 0) {
		rt::println("usage: cat <path>");
		return;
	};
	let buf: [512]u8 = [0...];
	const n = rt::readfile(*(&path: *str), buf[..]);
	if (n == 0) {
		rt::println("no such file");
		return;
	};
	rt::write(buf[..n]);
	if (buf[n - 1] != ('\n': u8)) {
		rt::println("");
	};
};

fn do_user(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: user <path>");
		return;
	};
	const pid = rt::spawn(*(&rest: *str));
	if (pid == ~0u64) {
		rt::println("cannot spawn");
		return;
	};
	for (rt::alive(pid)) {
		rt::cop();
	};
	rt::println("user process exited");
};

fn multi() void = {
	let ids: [3]u64 = [0u64, 0u64, 0u64];
	for (let i = 0z; i < 3; i += 1) {
		let arg: [8]u8 = [0...];
		arg[0] = '/': u8;
		arg[1] = 's': u8;
		arg[2] = 'p': u8;
		arg[3] = 'i': u8;
		arg[4] = 'n': u8;
		arg[5] = ' ': u8;
		arg[6] = ('1': u8) + (i: u8);
		const s = *(&arg[..7]: *str);
		ids[i] = rt::spawn(s);
	};
	for (true) {
		let live = false;
		for (let i = 0z; i < 3; i += 1) {
			if (rt::alive(ids[i])) {
				live = true;
			};
		};
		if (!live) {
			break;
		};
		rt::cop();
	};
	rt::println("all user processes exited");
};

// Reads one line from the keyboard, editing it as it goes. Everything the
// reader can do to a line that does not change it - moving the cursor, walking
// the history, finishing a word - happens in here, and only the finished line
// is left behind for the caller.
fn read_line() []u8 = {
	n = 0z;
	cur = 0z;
	shown = 0z;
	hpos = hcount;
	for (true) {
		// Each terminal window has a shell of its own, so there is no second
		// prompt to give when another one is opened.
		const c = read_key();
		if (c == ('\n': u8) || c == ('\r': u8)) {
			rt::println("");
			break;
		};
		if (c == 3) {
			// Ctrl-C gives up on the line rather than on the shell.
			rt::println("^C");
			n = 0z;
			cur = 0z;
			lb[0] = 0;
			break;
		};
		if (c == 12) {
			// Ctrl-L clears the screen and draws the line again on top of it.
			clear_screen();
			rt::print("ush> ");
			shown = 0z;
			redraw();
			continue;
		};
		if (c == 21) {
			// Ctrl-U empties the line.
			n = 0z;
			cur = 0z;
			redraw();
			continue;
		};
		if (c == 23) {
			// Ctrl-W takes off the word before the cursor: first the blanks
			// before it, then the word itself.
			let k = cur;
			for (let i = 0u64; k > 0 && lib::is_space(lb[k - 1]); i += 1) {
				k -= 1;
			};
			for (let i = 0u64; k > 0 && !lib::is_space(lb[k - 1]); i += 1) {
				k -= 1;
			};
			splice(k, cur, empty);
			continue;
		};
		if (c == 1 || c == KEY_HOME) {
			cur = 0z;
			redraw();
			continue;
		};
		if (c == 5 || c == KEY_END) {
			cur = n;
			redraw();
			continue;
		};
		if (c == 8 || c == 127) {
			if (cur > 0) {
				splice(cur - 1, cur, empty);
			};
			continue;
		};
		if (c == KEY_DEL) {
			if (cur < n) {
				splice(cur, cur + 1, empty);
			};
			continue;
		};
		if (c == KEY_LEFT) {
			if (cur > 0) {
				cur -= 1;
				showcur();
			};
			continue;
		};
		if (c == KEY_RIGHT) {
			if (cur < n) {
				cur += 1;
				showcur();
			};
			continue;
		};
		if (c == KEY_UP) {
			older();
			continue;
		};
		if (c == KEY_DOWN) {
			newer();
			continue;
		};
		if (c == ('\t': u8)) {
			complete();
			continue;
		};
		if (c >= (' ': u8) && c < 0x7F && n < LINEMAX) {
			// A printable byte goes in at the cursor, which may be in the
			// middle of what is already there.
			splice(cur, cur, one(c));
			continue;
		};
	};
	return lb[..n];
};

export @symbol("main") fn main() void = {
	const a = rt::arg();
	if (len(a) == 0) {
		rt::println("usage: cat <path>");
		return;
	};

	if (rt::strcmp(a, "/heap")) {
		let b: []u8 = [];
		for (let i = 0z; i < 8; i += 1) {
			append(b, ('A': u8) + (i: u8))!;
		};
		rt::print("heap: ");
		rt::write(b);
		rt::println("");
		free(b);
		return;
	};

	if (rt::strcmp(a, "/bad")) {
		rt::println("touching supervisor memory");
		const addr = 0x100000: uintptr;
		const p = addr: *u64;
		*p = 1;
		rt::println("should not reach here");
		return;
	};

	if (rt::strcmp(a, "/cons")) {
		const s: str = "written through /dev/cons\n";
		_ = rt::writefile("/dev/cons", *(&s: *[]u8));
		return;
	};

	if (rt::strcmp(a, "/note")) {
		const s: str = "a note from a user process\n";
		_ = rt::writefile("/dev/note", *(&s: *[]u8));
		let out: [256]u8 = [0...];
		const k = rt::readfile("/dev/note", out[..]);
		rt::print("note: ");
		rt::write(out[..k]);
		return;
	};

	if (rt::strcmp(a, "/ns")) {
		rt::println("namespace view of / :");
		let out: [256]u8 = [0...];
		let k = rt::readfile("/", out[..]);
		rt::write(out[..k]);
		const marker: str = "sealed with a private marker\n";
		_ = rt::create("/pp");
		_ = rt::writefile("/pp", *(&marker: *[]u8));
		k = rt::readfile("/pp", out[..]);
		rt::print("read back: ");
		rt::write(out[..k]);
		k = rt::readfile("/hello", out[..]);
		rt::print("shared /hello bytes: ");
		rt::printnum(k: u64);
		rt::println("");
		k = rt::readfile("/proc/self", out[..]);
		rt::print("this process: ");
		rt::write(out[..k]);
		return;
	};

	if (rt::strcmp(a, "/disk")) {
		let out: [512]u8 = [0...];
		const k = rt::readfile("/dev/disk", out[..]);
		rt::print("sector 0 holds ");
		rt::printnum(k: u64);
		rt::print(" bytes: ");
		let m = 0z;
		for (m < k && out[m] != ('\n': u8) && out[m] != 0) {
			rt::putc(out[m]);
			m += 1;
		};
		rt::println("");
		return;
	};

	if (starts(a, "/spin ")) {
		for (let i = 0u64; i < 4; i += 1) {
			rt::print(a);
			rt::print(" step ");
			rt::printnum(i);
			rt::println("");
			for (let j = 0u64; j < 4000000; j += 1) {
				void;
			};
		};
		return;
	};

	if (rt::strcmp(a, "/sh")) {
		rt::println("bunix user shell, type 'help'");
		load_bin();
		for (true) {
			rt::print("ush> ");
			const line = read_line();
			if (len(line) == 0) {
				continue;
			};
			remember();
			exec(line);
			if (quitting) {
				return;
			};
		};
	};

	let buf: [256]u8 = [0...];
	const k = rt::readfile(a, buf[..]);
	if (k == 0) {
		rt::print("cat: cannot read ");
		rt::println(a);
		return;
	};
	rt::write(buf[..k]);
};