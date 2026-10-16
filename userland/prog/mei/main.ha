// mei - a small full-screen editor for Bunix.
//
// The console hands out one byte at a time and writes one byte at a time, and
// escape sequences pass through it untouched, so a full-screen editor works
// here after all: mei turns the serial terminal into the only screen (the VGA
// text console would only render the escapes as rubbish), clears it, and draws
// the file itself. Cursor keys arrive from the kernel as the escape sequences a
// terminal sends, so they are handled the same way.
//
// Everything is held in memory: the buffer is the file, and saving writes it
// back out whole. The file is limited by MAXLINES and MAXCOLS, which is far more
// room than the examples in /usr/src need.
//
// Keys:
//   arrows, Home/End/PgUp/PgDn  move
//   Backspace, Delete           delete the character before / under the cursor
//   Enter                       split the line
//   Tab                         insert spaces to the next multiple of 4
//   Ctrl-S                      save            Ctrl-Q  quit
//   Ctrl-X                      save and quit   Ctrl-K  delete the line
//   Ctrl-Home / Ctrl-End       first / last line
//
// mei takes the file to edit as its argument, like `mei /tmp/x.c`.

use lib;
use rt;

def MAXLINES: size = 512;
def MAXCOLS: size = 200;
def TABSTOP: size = 4;

// The cursor and Home/End keys travel over the serial line as CSI A through
// CSI F. They are given codes above the typed range the moment they are read,
// because A to F are ordinary letters and an editor has to be able to type
// them: treating a typed A as "up" makes half the alphabet unreachable.
def KEY_UP: u8 = 0xE1;
def KEY_DOWN: u8 = 0xE2;
def KEY_RIGHT: u8 = 0xE3;
def KEY_LEFT: u8 = 0xE4;
def KEY_HOME: u8 = 0xE5;
def KEY_END: u8 = 0xE6;
def KEY_INS: u8 = 0xE7;

// The window is fitted to the console at startup. One row is kept for the
// message line, and the gutter is five columns wide.
let ROWS: size = 20;
let SCRCOLS: size = 78;

let lines: [MAXLINES][MAXCOLS]u8 = [[0...]...];
let llens: [MAXLINES]size = [0...];
let nlines: size = 1;
let outbuf: [65536]u8 = [0...];
let pathbuf: [256]u8 = [0...];
let plen: size = 0;
let dirty = false;
let msgbuf: [120]u8 = [0...];
let msglen: size = 0;
let msgset = false;

// Where the cursor is: a line and a column within it.
let curline: size = 0;
let curcol: size = 0;
// Which row of the screen the top of the window is showing.
let top: size = 0;

fn path() str = {
	return *(&pathbuf[..plen]: *str);
};

fn say(s: str) void = {
	const b = *(&s: *[]u8);
	let n = len(b);
	if (n > len(msgbuf)) {
		n = len(msgbuf);
	};
	for (let i = 0z; i < n; i += 1) {
		msgbuf[i] = b[i];
	};
	msglen = n;
	msgset = true;
};

// say replaces the whole message, so building one out of more than one piece
// needs this to keep what has already been written.
fn add(s: str) void = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b) && msglen < len(msgbuf); i += 1) {
		msgbuf[msglen] = b[i];
		msglen += 1;
	};
	msgset = true;
};

fn saynum(prefix: str, v: size) void = {
	say(prefix);
	append_num(msgbuf[..], &msglen, v);
};

// Escape sequences. These go to the terminal as ordinary bytes.
fn esc(s: str) void = {
	rt::write(*(&s: *[]u8));
};

fn at(row: size, col: size) void = {
	// CSI <row> ; <col> H, counting from one.
	let buf: [16]u8 = [0...];
	buf[0] = 0x1B;
	buf[1] = 0x5B;
	let i = 2z;
	put_num(buf[..], &i, row + 1);
	buf[i] = (';': u8);
	i += 1;
	put_num(buf[..], &i, col + 1);
	buf[i] = ('H': u8);
	i += 1;
	rt::write(buf[..i]);
};

// Writes a number in decimal at the end of buf, moving the write position on.
fn put_num(buf: []u8, at: *size, v: size) void = {
	let tmp: [20]u8 = [0...];
	let k = len(tmp);
	if (v == 0) {
		k -= 1;
		tmp[k] = ('0': u8);
	} else {
		let n = v;
		for (n > 0) {
			k -= 1;
			tmp[k] = ((n % 10): u8) + ('0': u8);
			n /= 10;
		};
	};
	// The digits were filled in from the end, so the number runs from k up to
	// the end of tmp. Each is written where the position points, then the
	// position moves on.
	for (let j = k; j < len(tmp) && *at < len(buf); j += 1) {
		buf[*at] = tmp[j];
		*at = *at + 1;
	};
};

fn clear() void = {
	esc("\x1b[2J\x1b[H");
};

fn clr_line() void = {
	esc("\x1b[K");
};

// One input byte, or 0 when nothing has arrived.
fn getch() u8 = {
	for (true) {
		const c = rt::readchr();
		if (c == 0) {
			rt::cop();
			continue;
		};
		return c;
	};
};

fn load() void = {
	nlines = 0;
	const n = rt::readfile(path(), outbuf[..]);
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || outbuf[i] == '\n') {
			add_line(outbuf[start..i]);
			start = i + 1;
		};
	};
	if (nlines == 0) {
		add_line(outbuf[..0]);
	};
	// A file that ends in a newline has no extra empty line after it.
	if (n > 0 && outbuf[n - 1] == '\n' && nlines > 1) {
		nlines -= 1;
	};
	curline = 0;
	curcol = 0;
	top = 0;
	dirty = false;
	touch_all();
};

fn add_line(s: []u8) void = {
	if (nlines >= MAXLINES) {
		return;
	};
	let k = len(s);
	if (k > MAXCOLS) {
		k = MAXCOLS;
	};
	for (let i = 0z; i < k; i += 1) {
		lines[nlines][i] = s[i];
	};
	llens[nlines] = k;
	nlines += 1;
};

fn move_line(dst: size, src: size) void = {
	llens[dst] = llens[src];
	for (let i = 0z; i < llens[src]; i += 1) {
		lines[dst][i] = lines[src][i];
	};
};

fn clamp_cursor() void = {
	if (curline >= nlines) {
		curline = if (nlines > 0) nlines - 1 else 0;
	};
	if (curcol > llens[curline]) {
		curcol = llens[curline];
	};
};

fn save() bool = {
	let n = 0z;
	for (let i = 0z; i < nlines; i += 1) {
		for (let j = 0z; j < llens[i] && n < len(outbuf); j += 1) {
			outbuf[n] = lines[i][j];
			n += 1;
		};
		if (n < len(outbuf)) {
			outbuf[n] = '\n';
			n += 1;
		};
	};
	const k = rt::writefile(path(), outbuf[..n]);
	if (k == 0) {
		say("mei: could not write the file");
		return false;
	};
	dirty = false;
	saynum("mei: wrote ", k);
	// Appended rather than said, so the count written above is kept.
	add(" bytes");
	return true;
};

// The line number, right aligned in the gutter, followed by a space.
fn gutter_of(li: size) void = {
	let num = li + 1;
	let digits = 1;
	if (num >= 1000) {
		digits = 4;
	} else if (num >= 100) {
		digits = 3;
	} else if (num >= 10) {
		digits = 2;
	};
	let buf: [10]u8 = [0...];
	let i = 0z;
	for (let s = digits; s < 4; s += 1) {
		buf[i] = (' ': u8);
		i += 1;
	};
	append_num(buf[..], &i, num);
	// A tilde after the number, the way nano and vim mark where a row stops.
	buf[i] = ('~': u8);
	i += 1;
	rt::write(buf[..i]);
};

// Rows past the end of the file get a bare tilde, so the end of the text is
// visible rather than having to be counted.
fn gutter_past_end() void = {
	const s: str = "    ~";
	rt::write(*(&s: *[]u8));
};

// Redraw the whole window. Simple, and at this size cheap enough.
// Which rows need drawing again. Keeping this narrow is what stops the screen
// being wiped and rebuilt for every keystroke: a full-screen program that
// redraws everything each time flickers, however quickly the kernel draws it.
let dlo: size = 0;
let dhi: size = 0;
let drew_top: size = 0;
let drew_rows: size = 0;
let drew_all = false;

// Marks a row as needing to be drawn again.
fn touch(r: size) void = {
	if (r >= ROWS) {
		return;
	};
	if (dlo <= dhi) {
		if (r < dlo) {
			dlo = r;
		};
		if (r > dhi) {
			dhi = r;
		};
	} else {
		dlo = r;
		dhi = r;
	};
};

// Marks every row as needing to be drawn again.
fn touch_all() void = {
	dlo = 0;
	dhi = ROWS - 1;
};

// One screen row: the gutter, the text, and the rest of the line cleared.
fn draw_row(r: size) void = {
	const li = top + r;
	at(r, 0);
	if (li < nlines) {
		// The last row is the message line, so it gets a blank gutter.
		if (r + 1 < ROWS) {
			gutter_of(li);
		} else {
			const pad: str = "     ";
			rt::write(*(&pad: *[]u8));
		};
		const body = lines[li];
		let n = llens[li];
		if (n > SCRCOLS) {
			n = SCRCOLS;
		};
		rt::write(body[..n]);
	} else if (r + 1 < ROWS) {
		// Past the end of the file: show where it stopped.
		gutter_past_end();
	};
	clr_line();
};

fn draw() void = {
	// A change of size or a first paint means everything on screen is wrong.
	if (drew_all || top != drew_top || ROWS != drew_rows) {
		clear();
		touch_all();
		drew_all = true;
		drew_top = top;
		drew_rows = ROWS;
	};
	for (let r = dlo; r <= dhi; r += 1) {
		draw_row(r);
	};
	dlo = ROWS;
	dhi = 0;
	// The bottom row is the status line, unless a message is showing.
	at(ROWS, 0);
	if (msgset) {
		rt::write(msgbuf[..msglen]);
		clr_line();
		msgset = false;
	} else {
		const lead: str = "mei ";
		const sep: str = "  ";
		rt::write(*(&lead: *[]u8));
		rt::write(pathbuf[..plen]);
		rt::write(*(&sep: *[]u8));
		let info: [64]u8 = [0...];
		let i = 0z;
		append_str(info[..], &i, "ln ");
		append_num(info[..], &i, curline + 1);
		append_str(info[..], &i, "/");
		append_num(info[..], &i, nlines);
		append_str(info[..], &i, "  col ");
		append_num(info[..], &i, curcol + 1);
		if (dirty) {
			append_str(info[..], &i, "  [modified]");
		};
		rt::write(info[..i]);
		clr_line();
	};
	// Put the cursor where the text is.
	at(curline - top, gutter() + curcol);
};

fn gutter() size = {
	return 5;
};

// Fit the window to the console the kernel reports, so the editor covers the
// whole screen instead of assuming one.
fn fit_screen() void = {
	const r = rt::screen_rows();
	const w = rt::screen_cols();
	if (r > 4) {
		// One row for the message line.
		ROWS = r: size - 1;
	};
	if (w > 12) {
		// Whatever the gutter does not use is left for the text itself.
		SCRCOLS = w: size - gutter();
	};
	if (ROWS > MAXLINES) {
		ROWS = MAXLINES;
	};
};

// The size the current layout was worked out for.
let fit_rows: size = 0;
let fit_cols: size = 0;

// The screen can change size while the editor is open, so the layout is worked
// out again on the way round the loop. The common case costs one comparison,
// because the size only has to be read again once it really moves.
fn refit() void = {
	const r = rt::screen_rows(): size;
	const w = rt::screen_cols(): size;
	if (r == fit_rows && w == fit_cols) {
		return;
	};
	fit_rows = r;
	fit_cols = w;
	fit_screen();
	// A shorter window may not show the cursor any more, and a narrower one
	// leaves less text on each row.
	clamp_cursor();
	scroll_to_cursor();
};

fn append_str(buf: []u8, at: *size, s: str) void = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b) && *at < len(buf); i += 1) {
		buf[*at] = b[i];
		*at = *at + 1;
	};
};

fn append_num(buf: []u8, at: *size, v: size) void = {
	let tmp: [20]u8 = [0...];
	let k = len(tmp);
	if (v == 0) {
		k -= 1;
		tmp[k] = '0': u8;
	} else {
		let n = v;
		for (n > 0) {
			k -= 1;
			tmp[k] = ((n % 10): u8) + ('0': u8);
			n /= 10;
		};
	};
	for (let j = k; j < len(tmp) && *at < len(buf); j += 1) {
		buf[*at] = tmp[j];
		*at = *at + 1;
	};
};

fn scroll_to_cursor() void = {
	if (curline < top) {
		top = curline;
	};
	if (curline >= top + ROWS - 1) {
		top = curline - (ROWS - 2);
	};
	touch_all();
};

// Insert a character at the cursor.
fn insert_char(c: u8) void = {
	const ln = curline;
	if (llens[ln] >= MAXCOLS) {
		say("mei: line too long");
		return;
	};
	const from = llens[ln];
	for (let i = from; i > curcol; i -= 1) {
		lines[ln][i] = lines[ln][i - 1];
	};
	lines[ln][curcol] = c;
	llens[ln] += 1;
	curcol += 1;
	dirty = true;
	touch(curline);
};

fn delete_char() void = {
	const ln = curline;
	if (curcol == 0) {
		return;
	};
	const from = curcol - 1;
	for (let i = from; i + 1 < llens[ln]; i += 1) {
		lines[ln][i] = lines[ln][i + 1];
	};
	llens[ln] -= 1;
	curcol -= 1;
	dirty = true;
	touch(curline);
};

fn delete_forward() void = {
	const ln = curline;
	if (curcol >= llens[ln]) {
		return;
	};
	const from = curcol;
	for (let i = from; i + 1 < llens[ln]; i += 1) {
		lines[ln][i] = lines[ln][i + 1];
	};
	llens[ln] -= 1;
	dirty = true;
	touch(curline);
};

// Enter: break the line here.
fn split_line() void = {
	const ln = curline;
	if (nlines >= MAXLINES) {
		say("mei: too many lines");
		return;
	};
	let j = nlines;
	for (j > ln + 1) {
		move_line(j, j - 1);
		j -= 1;
	};
	// The tail after the cursor becomes the new line.
	const tail = llens[ln] - curcol;
	llens[ln + 1] = tail;
	for (let i = 0z; i < tail; i += 1) {
		lines[ln + 1][i] = lines[ln][curcol + i];
	};
	llens[ln] = curcol;
	nlines += 1;
	curline += 1;
	curcol = 0;
	dirty = true;
	touch(curline - 1);
	touch(curline);
};

fn join_prev() void = {
	if (curline == 0) {
		return;
	};
	const ln = curline;
	let prev = ln - 1;
	if (llens[prev] + llens[ln] > MAXCOLS) {
		say("mei: joined line would be too long");
		return;
	};
	let at = llens[prev];
	for (let i = 0z; i < llens[ln]; i += 1) {
		lines[prev][at + i] = lines[ln][i];
	};
	llens[prev] += llens[ln];
	// Drop the line we merged in.
	let j = prev;
	for (j + 1 < nlines) {
		move_line(j, j + 1);
		j += 1;
	};
	nlines -= 1;
	curline = prev;
	curcol = at;
	dirty = true;
	touch(curline);
	touch(curline + 1);
};

fn kill_line() void = {
	if (nlines == 1) {
		llens[0] = 0;
		curcol = 0;
		dirty = true;
		return;
	};
	let j = curline;
	for (j + 1 < nlines) {
		move_line(j, j + 1);
		j += 1;
	};
	nlines -= 1;
	clamp_cursor();
	dirty = true;
	touch_all();
};

fn insert_newline_before() void = {
	if (nlines >= MAXLINES) {
		say("mei: too many lines");
		return;
	};
	let j = nlines;
	for (j > curline) {
		move_line(j, j - 1);
		j -= 1;
	};
	llens[curline] = 0;
	nlines += 1;
	curcol = 0;
	dirty = true;
	touch(curline - 1);
	touch(curline);
};

// Read the next input byte. Escape sequences arrive one byte at a time, so an
// escape is collected here and the byte after it decides what the key was.
fn key() u8 = {
	let c = getch();
	if (c != 0x1B) {
		return c;
	};
	// An escape on its own is the Escape key; give the rest a moment.
	let n = getch();
	if (n == 0x5B) {
		const m = getch();
		// Home, End, the paging keys, Insert and Delete come as a digit
		// followed by a tilde. The digit comes first, so the tilde has to be
		// read and dropped, or it ends up typed into the file.
		if (m >= ('0': u8) && m <= ('9': u8)) {
			const t = getch();
			if (t != ('~': u8)) {
				return 0x1B;
			};
			if (m == ('1': u8)) {
				return KEY_HOME;
			};
			if (m == ('4': u8)) {
				return KEY_END;
			};
			if (m == ('3': u8)) {
				return 0x7F;   // Delete
			};
			if (m == ('2': u8)) {
				return KEY_INS;
			};
			if (m == ('5': u8)) {
				return 0xF1;   // Page Up
			};
			if (m == ('6': u8)) {
				return 0xF2;   // Page Down
			};
			return 0x1B;
		};
		// A single letter after CSI is a cursor key.
		if (m == 0x41) {
			return KEY_UP;
		};
		if (m == 0x42) {
			return KEY_DOWN;
		};
		if (m == 0x43) {
			return KEY_RIGHT;
		};
		if (m == 0x44) {
			return KEY_LEFT;
		};
		if (m == 0x48) {
			return KEY_HOME;
		};
		if (m == 0x46) {
			return KEY_END;
		};
		return m;
	};
	return 0x1B;
};

fn quit_check() bool = {
	// Returns true when it is fine to leave.
	if (!dirty) {
		return true;
	};
	say("mei: unsaved changes (Ctrl-X saves and quits, Ctrl-Q again discards)");
	return false;
};

export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	if (len(arg) == 0) {
		rt::println("usage: mei <file>");
		return;
	};
	let k = len(arg);
	if (k > len(pathbuf)) {
		k = len(pathbuf);
	};
	for (let i = 0z; i < k; i += 1) {
		pathbuf[i] = arg[i];
	};
	plen = k;

	refit();
	load();

	// An initial message, replaced by the status line once anything happens.
	if (nlines == 1 && llens[0] == 0) {
		say("mei: new file. type to write, ^S save, ^Q quit");
	} else {
		say("^S save  ^X save+quit  ^Q quit  arrows move");
	};

	let running = true;
	for (running) {
		refit();
		draw();
		const k = key();
		if (k == 0x11) {                 // Ctrl-Q
			running = quit_check();
		} else if (k == 0x13) {          // Ctrl-S
			save();
		} else if (k == 0x18) {          // Ctrl-X
			if (save()) {
				running = false;
			};
		} else if (k == 0x0B) {          // Ctrl-K
			kill_line();
		} else if (k == 0x08) {          // Ctrl-H, same as Backspace
			delete_char();
		} else if (k == 0x7F) {          // Delete
			delete_forward();
		} else if (k == '\n' || k == '\r') {
			split_line();
		} else if (k == '\t') {
			for (let i = curcol; i % TABSTOP != 0; i += 1) {
				insert_char((' ': u8));
			};
		} else if (k == KEY_UP) {
			if (curline > 0) {
				curline -= 1;
			};
		} else if (k == KEY_DOWN) {
			if (curline + 1 < nlines) {
				curline += 1;
			};
		} else if (k == KEY_RIGHT) {
			if (curcol < llens[curline]) {
				curcol += 1;
			};
		} else if (k == KEY_LEFT) {
			if (curcol > 0) {
				curcol -= 1;
			};
		} else if (k == KEY_HOME || k == KEY_END) {
			curcol = if (k == KEY_HOME) 0 else llens[curline];
		} else if (k == KEY_INS) {       // Insert
			insert_char(' ');
			delete_forward();
		} else if (k == 0xF3) {          // Home
			curcol = 0;
		} else if (k == 0xF4) {          // End
			curcol = llens[curline];
		} else if (k == 0xF1) {          // Page Up
			for (let i = 0z; i < ROWS - 2 && curline > 0; i += 1) {
				curline -= 1;
			};
		} else if (k == 0xF2) {          // Page Down
			for (let i = 0z; i < ROWS - 2 && curline + 1 < nlines; i += 1) {
				curline += 1;
			};
		} else if (k >= 0x20 && k < 0x7F) {
			insert_char(k);
		};
		clamp_cursor();
		scroll_to_cursor();
	};

	// The window, the gutter and the status line all belong to the editor and
	// mean nothing once it has closed, so the screen is cleared and the cursor
	// put back at the top. Otherwise the shell's next prompt lands in the
	// middle of the tilde rows.
	clear();
	rt::print("mei: left ");
	rt::println(path());
};
