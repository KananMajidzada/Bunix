use architecture;
use fb;
use mem;
use rt;

// kit: the window manager the machine boots into. A plain desktop holds
// terminals drawn as flat rectangles: a title bar to drag, a frame that turns
// black under the pointer so an edge can be grabbed to resize, and a scrollbar
// on the right edge. Button 1 selects, moves, and resizes; buttons 2 and 3
// raise a menu. Window changes repaint the whole desktop into the framebuffer
// shadow, so moving or resizing never leaves a trail behind. Terminal output
// is instead batched: writes mark the window dirty and one frame is drawn when
// the loop next waits for input, so a command's output costs one repaint
// rather than one per letter or line.

def MAXWIN: size = 6;
def MAXCOLS: size = 120;
def MAXROWS: size = 40;
def HIST: size = 256;
def BORD: size = 3;
def TITLE: size = 22;
def SB: size = 12;
def EDGE: size = 6;
def MINCOLS: size = 16;
def MINROWS: size = 4;
def NONE: size = 1000;

def DESKTOP: u32 = 0xC9C9C9;
def FRAME: u32 = 0x5A5A5A;
def FRAMEHI: u32 = 0x000000;
def TITLEBG: u32 = 0x3B3B3B;
def TITLEIDLE: u32 = 0xB0B0B0;
def TRACK: u32 = 0xDCDCDC;
def THUMB: u32 = 0x8C8C8C;
def MENUSEL: u32 = 0x3B3B3B;

def MI: size = 6;
def IH: size = 20;
// The square on a drawing window's title bar that fills the screen with it,
// or puts it back where it was.
def GBTN: size = 14;
// The size a drawing window starts at: the game's own picture, one pixel of
// it to one pixel of the window, with nothing scaled until the player asks
// for more window than that.
def GDEFW: size = 640;
def GDEFH: size = 400;

const MITEMS: [6]str = ["new", "resize", "move", "delete", "hide", "exit"];

// Pointer: a 14x14 arrow, stored as art. 0 leaves the pixel alone, 1 is the
// white outline and 2 is the black it fills, so the shape carries its own
// edge and nothing has to be drawn around it afterwards. The tip in the top
// left corner is the hotspot: it lands on where the pointer really is.
def PW: size = 14;
def PH: size = 14;
def CUR_EDGE: u8 = 1;	// the white line round the shape
def CUR_FILL: u8 = 2;	// the black inside it

const CUR: [196]u8 = [
	1,1,1,1,1,1,1,1,1,0,0,0,0,0,
	1,2,2,2,2,2,2,2,1,0,0,0,0,0,
	1,2,2,2,2,2,2,2,1,0,0,0,0,0,
	1,2,2,2,2,1,1,1,1,0,0,0,0,0,
	1,2,2,2,2,2,1,1,0,0,0,0,0,0,
	1,2,2,1,2,2,2,1,1,0,0,0,0,0,
	1,2,2,1,1,2,2,2,1,1,0,0,0,0,
	1,2,2,1,1,1,2,2,2,1,1,0,0,0,
	1,1,1,1,0,1,1,2,2,2,1,1,0,0,
	0,0,0,0,0,0,1,1,2,2,2,1,1,0,
	0,0,0,0,0,0,0,1,1,2,2,2,1,1,
	0,0,0,0,0,0,0,0,1,1,2,2,2,1,
	0,0,0,0,0,0,0,0,0,1,1,2,1,1,
	0,0,0,0,0,0,0,0,0,0,1,1,1,0,
];

type win = struct {
	used: bool,
	hidden: bool,
	wx: size, wy: size, ww: size, wh: size,
	cols: size, rows: size,
	total: size, top: size, crow: size, ccol: size,
	// A drawing window holds pixels rather than text: a program writes its
	// frame straight into the window, and kit keeps the last one so the
	// window can be put back when something else has been drawn over it.
	graphic: bool,
	gbuf: uintptr,		// the picture, gw by gh 32-bit pixels
	gpages: size,		// the frames gbuf was taken from
	gw: size, gh: size,	// the picture's size, which is the program's screen
	full: bool,			// grown over the whole display
	fsavx: size, fsavy: size, fsvw: size, fsvh: size,	// where it was before
	gname: [16]u8, gnlen: size,	// what the title bar calls it
	owner: size,		// the thread the window was made for
	gterm: size,		// the terminal that thread's own words still go to
};

let on = false;
let wins: [MAXWIN]win = [win { ... }...];
let bufs: [MAXWIN * HIST * MAXCOLS]u8 = [0...];
let zlist: [MAXWIN]size = [0...];
let nz = 0z;
let focus: size = NONE;

let mx = 0z;
let my = 0z;
let lastbtn: u8 = 0;
let hover: size = NONE;

// The buttons a drawing program has down, taken while the pointer was over
// its picture. They stay the program's until they come up again, so a press
// made there is always answered with its release, wherever the pointer has
// wandered to by then.
let appbtn: u8 = 0;

let grab: u8 = 0;	// 1 move, 2 resize, held with button 1
let gwin: size = NONE;
let gedge: u8 = 0;
let gox = 0z;
let goy = 0z;
let gwx = 0z;
let gwy = 0z;
let gww = 0z;
let gwh = 0z;
let grx = 0z;	// pointer where the resize grab began
let gry = 0z;
let fmode: u8 = 0;	// 1 move, 2 resize, driven from the menu
let sbdrag = false;
let sbwin: size = NONE;

let menu_open = false;
let menu_btn: u8 = 0;
let menu_sel = -1;
let menu_win: size = NONE;
let menu_x = 0z;
let menu_y = 0z;

// Set when the text buffers changed but the screen has not caught up yet.
// Terminal writes only mark this; the frame is drawn once the waiting loop
// next polls for input, so a burst of output costs one repaint instead of one
// per character or per line.
// The window that has the focus. Keystrokes belong to it rather than to
// whichever thread happened to be running when they arrived.
export fn focus_win() size = return focus;

// The window output is currently going to. A thread writes to the window it
// was started in rather than to whichever one happens to have the focus, so a
// program left running in one terminal does not paint over another. NONE means
// there is no window to write to yet, and the focused window is used instead.
let out_win: size = NONE;

// The scheduler calls this on every thread switch.
export fn set_out_win(wi: size) void = {
	out_win = wi;
};

// The window a byte written now should land in. A drawing window has no room
// for words, so a program drawing into one still has its own output go to the
// terminal it started in; when that terminal is gone the words are dropped
// rather than left lying about the picture.
export fn out_target() size = {
	let wi = if (out_win != NONE && out_win < MAXWIN && wins[out_win].used) {
		yield out_win;
	} else {
		yield focus;
	};
	if (wi != NONE && wi < MAXWIN && wins[wi].used && wins[wi].graphic) {
		const t = wins[wi].gterm;
		return if (t != NONE && t < MAXWIN && wins[t].used && !wins[t].graphic) {
			yield t;
		} else {
			yield NONE;
		};
	};
	return wi;
};

// The drawing window of whichever thread the kernel is running now, which is
// where its writes to /dev/fb land. NONE for a program that draws at the
// screen itself, such as a test that fills the display with a pattern.
export fn gfx_window() size = {
	if (on && out_win != NONE && out_win < MAXWIN && wins[out_win].used
			&& wins[out_win].graphic) {
		return out_win;
	};
	return NONE;
};

// The size of the picture the running thread draws into, in pixels, and zero
// by zero for a thread that draws at the screen itself - which is how a
// program is told it has no window of its own.
export fn gfx_dims(w: *size, h: *size) void = {
	const wi = gfx_window();
	if (wi == NONE) {
		*w = 0;
		*h = 0;
		return;
	};
	*w = wins[wi].gw;
	*h = wins[wi].gh;
};

// Set to the window whose contents changed. Terminal output only ever affects
// the window it was written to, so redrawing the desktop behind it for every
// keystroke is what makes a full-screen program flicker.
let dirty_win: size = NONE;

// Set when a window is created after boot, so the shell knows to greet the new
// terminal. Cleared by take_fresh once the prompt has been drawn.
let fresh = false;

export fn take_fresh() bool = {
	if (!fresh) {
		return false;
	};
	fresh = false;
	return true;
};

export fn active() bool = {
	return on;
};

fn slen(s: str) size = len(*(&s: *[]u8));

fn base(wi: size) size = wi * HIST * MAXCOLS;
fn at(wi: size, li: size, c: size) size = base(wi) + li * MAXCOLS + c;

fn layout(wi: size) void = {
	wins[wi].ww = wins[wi].cols * fb::CW + 2 * BORD + SB;
	wins[wi].wh = TITLE + 2 * BORD + wins[wi].rows * fb::CH;
};

fn sbx(wi: size) size = wins[wi].wx + BORD + wins[wi].cols * fb::CW;
fn sby(wi: size) size = wins[wi].wy + TITLE + BORD;

fn clamp(n: int, hi: int) int = {
	if (n < 0) {
		return 0;
	};
	if (n > hi) {
		return hi;
	};
	return n;
};

fn clampv(v: int, lo: int, hi: int) int = {
	if (v < lo) {
		return lo;
	};
	if (v > hi) {
		return hi;
	};
	return v;
};

// A rectangle of the screen, so the pieces of it a draw touches can be named.
type rect = struct {
	x: size, y: size, w: size, h: size,
};

// The rectangle a window draws into. A hidden window is only a title bar, and
// that is all the screen ever sees of it.
fn drawn(wi: size) rect = {
	if (wins[wi].hidden) {
		return rect { x = wins[wi].wx, y = wins[wi].wy, w = wins[wi].ww, h = TITLE };
	};
	return rect { x = wins[wi].wx, y = wins[wi].wy, w = wins[wi].ww, h = wins[wi].wh };
};

// ---------------------------------------------------------------------------
// Drawing windows.
//
// A drawing window belongs to a program that asked for one by writing its
// name to /dev/win: it is a rectangle of pixels rather than a grid of text,
// sized to whatever the program reports it draws, and the program paints it
// by writing /dev/fb. Kit keeps the last frame the program wrote so the
// window can be repainted whenever something is drawn over or moved across
// it, which is what lets a game and the desktop share the screen without
// either leaving marks on the other.

// The window's title, as the title bar draws it. A text window is a terminal;
// a drawing window is called whatever its program named it.
let titlebuf: [16]u8 = [0...];

fn title_of(wi: size) str = {
	if (!wins[wi].graphic) {
		return "term";
	};
	const n = wins[wi].gnlen;
	for (let i = 0z; i < n; i += 1) {
		titlebuf[i] = wins[wi].gname[i];
	};
	return *(&titlebuf[..n]: *str);
};

fn set_name(wi: size, name: []u8) void = {
	let n = len(name);
	if (n > 15) {
		n = 15;
	};
	if (n == 0) {
		wins[wi].gname[0] = 'a': u8;
		wins[wi].gname[1] = 'p': u8;
		wins[wi].gname[2] = 'p': u8;
		wins[wi].gnlen = 3;
		return;
	};
	for (let i = 0z; i < n; i += 1) {
		wins[wi].gname[i] = name[i];
	};
	wins[wi].gnlen = n;
};

// The frame that goes around a picture of the given size.
fn glayout(wi: size) void = {
	wins[wi].ww = wins[wi].gw + 2 * BORD;
	wins[wi].wh = TITLE + 2 * BORD + wins[wi].gh;
};

// Hands back the frames a picture was held in.
fn gfree(wi: size) void = {
	const p = wins[wi].gbuf;
	const n = wins[wi].gpages;
	for (let i = 0z; i < n; i += 1) {
		mem::release(p + ((i * 4096): uintptr));
	};
	wins[wi].gbuf = 0;
	wins[wi].gpages = 0;
	wins[wi].gw = 0;
	wins[wi].gh = 0;
};

// Makes a picture of w by h pixels for the window, carrying over whatever of
// the old one still fits. False when there is no room, and then nothing about
// the window has changed.
fn galloc(wi: size, w: size, h: size) bool = {
	if (w < 16 || h < 16) {
		return false;
	};
	const pages = (w * h * 4 + 4095) / 4096;
	const p = mem::frames_alloc(pages: u64);
	if (p == 0) {
		return false;
	};
	// Cleared a word at a time: whatever the old picture does not cover must
	// never show some other program's pixels.
	for (let i = 0z; i < pages * 4096 / 8; i += 1) {
		*((p + ((i * 8): uintptr)): *u64) = 0;
	};
	const old = wins[wi].gbuf;
	if (old != 0) {
		const ow = wins[wi].gw;
		const oh = wins[wi].gh;
		const cw = if (w < ow) w else ow;
		const ch = if (h < oh) h else oh;
		for (let j = 0z; j < ch; j += 1) {
			for (let i = 0z; i < cw; i += 1) {
				*((p + ((((j * w) + i) * 4): uintptr)): *u32) =
					*((old + ((((j * ow) + i) * 4): uintptr)): *u32);
			};
		};
		gfree(wi);
	};
	wins[wi].gbuf = p;
	wins[wi].gpages = pages;
	wins[wi].gw = w;
	wins[wi].gh = h;
	return true;
};

// Whether the pointer is on a window's picture rather than its frame, title,
// or scrollbar. That is where a drawing program's mouse belongs; everything
// around the picture stays the desktop's.
fn over_content(wi: size, x: size, y: size) bool = {
	return x >= wins[wi].wx + BORD
		&& x < wins[wi].wx + BORD + wins[wi].gw
		&& y >= wins[wi].wy + TITLE + BORD
		&& y < wins[wi].wy + TITLE + BORD + wins[wi].gh;
};

// The square on the title bar that fills the screen with a drawing window or
// puts it back, and whether the pointer is on it.
fn btn_x(wi: size) size = wins[wi].wx + wins[wi].ww - GBTN - 6;
fn btn_y(wi: size) size = wins[wi].wy + (TITLE - GBTN) / 2;

fn over_btn(wi: size, x: size, y: size) bool = {
	return x >= btn_x(wi) && x < btn_x(wi) + GBTN
		&& y >= btn_y(wi) && y < btn_y(wi) + GBTN;
};

fn draw_btn(wi: size) void = {
	const x = btn_x(wi);
	const y = btn_y(wi);
	const hot = mx >= x && mx < x + GBTN && my >= y && my < y + GBTN;
	const bg = if (hot) FRAME else TITLEBG;
	const fg = if (wi == focus) fb::WHITE else TITLEIDLE;
	fb::fill(x, y, GBTN, GBTN, bg);
	if (wins[wi].full) {
		// A square inside a square: back to a window again.
		outline(x + 3, y + 3, GBTN - 6, GBTN - 6, fg);
	} else {
		// A solid square: grow over the whole screen.
		outline(x, y, GBTN, GBTN, fg);
		fb::fill(x + 3, y + 3, GBTN - 6, GBTN - 6, fg);
	};
};

// Grows the window over the whole display, or puts it back where it was. The
// picture is made to fit either way and keeps what still fits of itself, and
// the program finds out by asking /dev/win for its size again.
fn set_full(wi: size, on2: bool) void = {
	if (wi == NONE || !wins[wi].used || !wins[wi].graphic
			|| wins[wi].full == on2) {
		return;
	};
	if (on2) {
		const w = fb::width() - 2 * BORD;
		const h = fb::height() - TITLE - 2 * BORD;
		if (!galloc(wi, w, h)) {
			return;
		};
		wins[wi].fsavx = wins[wi].wx;
		wins[wi].fsavy = wins[wi].wy;
		wins[wi].fsvw = wins[wi].ww;
		wins[wi].fsvh = wins[wi].wh;
		wins[wi].wx = 0;
		wins[wi].wy = 0;
		wins[wi].ww = fb::width();
		wins[wi].wh = fb::height();
	} else {
		const w = wins[wi].fsvw - 2 * BORD;
		const h = wins[wi].fsvh - TITLE - 2 * BORD;
		if (!galloc(wi, w, h)) {
			return;
		};
		wins[wi].wx = wins[wi].fsavx;
		wins[wi].wy = wins[wi].fsavy;
		wins[wi].ww = wins[wi].fsvw;
		wins[wi].wh = wins[wi].fsvh;
	};
	wins[wi].full = on2;
	raise(wi);
	focus = wi;
	repaint();
};

// The fullscreen a program asked for through /dev/win: '1' fills the screen,
// '0' puts the window back, anything else switches between the two.
export fn control_full(wi: size, c: u8) void = {
	if (wi == NONE || !wins[wi].used || !wins[wi].graphic) {
		return;
	};
	if (c == ('1': u8)) {
		set_full(wi, true);
	} else if (c == ('0': u8)) {
		set_full(wi, false);
	} else {
		set_full(wi, !wins[wi].full);
	};
};

// Shows the picture now in the window: the pixels go into the shadow, then
// whatever the desktop drew over them afterwards is put back on top of them,
// and only the rectangles that really changed reach the card. The program
// writes a frame sixty times a second, and none of that may spill onto a
// terminal sitting over the window.
fn show(wi: size) void = {
	if (wins[wi].hidden || wins[wi].gbuf == 0) {
		return;
	};
	const cx = wins[wi].wx + BORD;
	const cy = wins[wi].wy + TITLE + BORD;
	const cw = wins[wi].gw;
	const ch = wins[wi].gh;
	fb::blit(cx, cy, cw, ch, wins[wi].gbuf, cw * 4);
	fb::present_rect(cx, cy, cw, ch);
	// Windows raised above this one were drawn over the picture in z order,
	// so they go back in the same order and still come out on top.
	let zi = 0z;
	let found = false;
	for (let i = 0z; i < nz; i += 1) {
		if (zlist[i] == wi) {
			zi = i;
			found = true;
			break;
		};
	};
	if (found) {
		for (let j = zi + 1; j < nz; j += 1) {
			const wj = zlist[j];
			const r = drawn(wj);
			if (r.x >= cx + cw || r.x + r.w <= cx
					|| r.y >= cy + ch || r.y + r.h <= cy) {
				continue;
			};
			draw_window(wj);
			fb::present_rect(r.x, r.y, r.w, r.h);
		};
	};
	// The menu and the pointer are above everything, and were possibly under
	// the frame just shown.
	if (menu_open) {
		draw_menu();
		fb::present_rect(menu_x, menu_y, menu_w(), menu_h());
	};
	draw_pointer();
	fb::present_rect(mx, my, PW, PH);
};

// Puts a frame the program wrote into its window. The pixels are packed
// 32-bit, w by h with no padding, and off names a byte of that picture: the
// same shape /dev/fb has, only the picture is the window's own.
export fn draw_frame(wi: size, data: []u8, off: u64) size = {
	if (!on || wi == NONE || !wins[wi].used || !wins[wi].graphic) {
		return 0;
	};
	const gw = (wins[wi].gw: u64);
	const gh = (wins[wi].gh: u64);
	const total = gw * gh * 4;
	if (off >= total || len(data) == 0 || wins[wi].gbuf == 0) {
		return 0;
	};
	let n = (len(data): u64);
	if (off + n > total) {
		n = total - off;
	};
	const base = wins[wi].gbuf;
	let p = off / 4;
	let src = 0z;
	for (p < gw * gh && (src: u64) < n) {
		const y = p / gw;
		const x = p % gw;
		const dst = base + ((y * gw + x) * 4): uintptr;
		let room = (gw - x) * 4;
		if (room > n - (src: u64)) {
			room = n - (src: u64);
		};
		architecture::memcpy(dst, (&data[src]: uintptr), room: size);
		src += room: size;
		p += room / 4;
	};
	show(wi);
	return n: size;
};

// Takes the picture back out of a window, packed the same way, which is how a
// program saves what it drew and puts it back later.
export fn read_frame(wi: size, buf: []u8, off: u64, n: size) size = {
	if (!on || wi == NONE || !wins[wi].used || !wins[wi].graphic
			|| wins[wi].gbuf == 0) {
		return 0;
	};
	const gw = (wins[wi].gw: u64);
	const gh = (wins[wi].gh: u64);
	const total = gw * gh * 4;
	if (off >= total || n == 0) {
		return 0;
	};
	let got = (n: u64);
	if (off + got > total) {
		got = total - off;
	};
	const base = wins[wi].gbuf;
	let p = off / 4;
	let dst = 0z;
	for (p < gw * gh && (dst: u64) < got) {
		const y = p / gw;
		const x = p % gw;
		const src = base + ((y * gw + x) * 4): uintptr;
		let room = (gw - x) * 4;
		if (room > got - (dst: u64)) {
			room = got - (dst: u64);
		};
		architecture::memcpy((&buf[dst]: uintptr), src, room: size);
		dst += room: size;
		p += room / 4;
	};
	return dst;
};

// Makes a drawing window for a program that asked for one by writing its name
// to /dev/win, and hands it over: the window is focused at once, so keys and
// pointer belong to the program, while the program's own words keep going to
// the terminal it started in. NONE when there is no screen or no room.
export fn claim_gfx(name: []u8, id: size, from: size) size = {
	if (!on) {
		return NONE;
	};
	// Asking twice gives the same window; only the name changes.
	const have = gfx_window();
	if (have != NONE) {
		set_name(have, name);
		return have;
	};
	let wi = NONE;
	for (let i = 0z; i < MAXWIN; i += 1) {
		if (!wins[i].used) {
			wi = i;
			break;
		};
	};
	if (wi == NONE) {
		return NONE;
	};
	wins[wi].used = true;
	wins[wi].hidden = false;
	wins[wi].cols = 0;
	wins[wi].rows = 0;
	wins[wi].total = 1;
	wins[wi].top = 0;
	wins[wi].crow = 0;
	wins[wi].ccol = 0;
	wins[wi].graphic = true;
	wins[wi].gbuf = 0;
	wins[wi].gpages = 0;
	wins[wi].gw = 0;
	wins[wi].gh = 0;
	wins[wi].full = false;
	wins[wi].fsavx = 0;
	wins[wi].fsavy = 0;
	wins[wi].fsvw = 0;
	wins[wi].fsvh = 0;
	wins[wi].owner = id;
	wins[wi].gterm = if (from == wi) NONE else from;
	set_name(wi, name);
	if (!galloc(wi, GDEFW, GDEFH)) {
		wins[wi].used = false;
		return NONE;
	};
	glayout(wi);
	// Over the middle of the screen, where the picture is easy to look at.
	wins[wi].wx = (fb::width() - wins[wi].ww) / 2;
	wins[wi].wy = (fb::height() - wins[wi].wh) / 2;
	zlist[nz] = wi;
	nz += 1;
	focus = wi;
	appbtn = 0;
	repaint();
	return wi;
};

// The thread a drawing window was made for has stopped, so the window has
// nothing left to draw in it and goes: quitting a game leaves the desktop
// exactly as it was found.
export fn release_owner(id: size) void = {
	if (!on) {
		return;
	};
	let gone = false;
	for (let i = 0z; i < MAXWIN; i += 1) {
		if (wins[i].used && wins[i].graphic && wins[i].owner == id) {
			delete_window(i);
			gone = true;
		};
	};
	if (gone) {
		appbtn = 0;
		repaint();
	};
};


fn outline(x: size, y: size, w: size, h: size, c: u32) void = {
	fb::fill(x, y, w, 1, c);
	fb::fill(x, y + h - 1, w, 1, c);
	fb::fill(x, y, 1, h, c);
	fb::fill(x + w - 1, y, 1, h, c);
};

fn line(wi: size, r: size) void = {
	const li = wins[wi].top + r;
	for (let c = 0z; c < wins[wi].cols; c += 1) {
		const ch = if (li < HIST) bufs[at(wi, li, c)] else (' ': u8);
		fb::cell(wins[wi].wx + BORD + c * fb::CW,
			wins[wi].wy + TITLE + BORD + r * fb::CH,
			ch, fb::BLACK, fb::WHITE);
	};
};

fn draw_tcursor(wi: size) void = {
	const cw = wins[wi].crow;
	if (cw < wins[wi].top || cw >= wins[wi].top + wins[wi].rows) {
		return;
	};
	if (wins[wi].ccol >= wins[wi].cols) {
		return;
	};
	const r = cw - wins[wi].top;
	fb::cell(wins[wi].wx + BORD + wins[wi].ccol * fb::CW,
		wins[wi].wy + TITLE + BORD + r * fb::CH,
		bufs[at(wi, cw, wins[wi].ccol)], fb::WHITE, fb::BLACK);
};

fn draw_scrollbar(wi: size) void = {
	const sh = wins[wi].rows * fb::CH;
	fb::fill(sbx(wi), sby(wi), SB, sh, TRACK);
	if (wins[wi].total > wins[wi].rows) {
		let th = sh * wins[wi].rows / wins[wi].total;
		if (th < 20) {
			th = 20;
		};
		if (th > sh) {
			th = sh;
		};
		const span = sh - th;
		const maxtop = wins[wi].total - wins[wi].rows;
		let ty = if (span > 0) sby(wi) + span * wins[wi].top / maxtop
			else sby(wi);
		// The view can be one line past where the thumb belongs right after
		// a resize (the size clamp in apply_size runs before the next
		// write), and a thumb drawn past the track would spill over the
		// frame and the desktop.
		if (ty > sby(wi) + span) {
			ty = sby(wi) + span;
		};
		fb::fill(sbx(wi) + 1, ty, SB - 2, th, THUMB);
	};
};

fn draw_shade(wi: size) void = {
	const fc = if (hover == wi) FRAMEHI else FRAME;
	fb::fill(wins[wi].wx, wins[wi].wy, wins[wi].ww, TITLE, TITLEBG);
	fb::fill(wins[wi].wx, wins[wi].wy + TITLE - BORD, wins[wi].ww, BORD, fc);
	fb::text(wins[wi].wx + 6, wins[wi].wy + 3, title_of(wi), TITLEIDLE, TITLEBG);
};

// A drawing window: the frame of a terminal, with the program's picture inside
// it instead of a grid of text, and the button that grows it over the screen.
fn draw_gfx(wi: size) void = {
	if (wins[wi].hidden) {
		draw_shade(wi);
		return;
	};
	const fc = if (hover == wi) FRAMEHI else FRAME;
	fb::fill(wins[wi].wx, wins[wi].wy, wins[wi].ww, TITLE, TITLEBG);
	if (hover == wi) {
		fb::fill(wins[wi].wx, wins[wi].wy, wins[wi].ww, 1, FRAMEHI);
	};
	fb::fill(wins[wi].wx, wins[wi].wy + TITLE, BORD, wins[wi].wh - TITLE, fc);
	fb::fill(wins[wi].wx + wins[wi].ww - BORD, wins[wi].wy + TITLE, BORD,
		wins[wi].wh - TITLE, fc);
	fb::fill(wins[wi].wx, wins[wi].wy + wins[wi].wh - BORD, wins[wi].ww, BORD,
		fc);
	fb::fill(wins[wi].wx + BORD, wins[wi].wy + TITLE + BORD,
		wins[wi].ww - 2 * BORD, wins[wi].wh - TITLE - 2 * BORD, fb::WHITE);
	if (wins[wi].gbuf != 0) {
		fb::blit(wins[wi].wx + BORD, wins[wi].wy + TITLE + BORD,
			wins[wi].gw, wins[wi].gh, wins[wi].gbuf, wins[wi].gw * 4);
	};
	const tc = if (wi == focus) fb::WHITE else TITLEIDLE;
	fb::text(wins[wi].wx + 6, wins[wi].wy + 3, title_of(wi), tc, TITLEBG);
	draw_btn(wi);
};

fn draw_window(wi: size) void = {
	if (wins[wi].graphic) {
		draw_gfx(wi);
		return;
	};
	if (wins[wi].hidden) {
		draw_shade(wi);
		return;
	};
	const fc = if (hover == wi) FRAMEHI else FRAME;
	fb::fill(wins[wi].wx, wins[wi].wy, wins[wi].ww, TITLE, TITLEBG);
	if (hover == wi) {
		fb::fill(wins[wi].wx, wins[wi].wy, wins[wi].ww, 1, FRAMEHI);
	};
	fb::fill(wins[wi].wx, wins[wi].wy + TITLE, BORD, wins[wi].wh - TITLE, fc);
	fb::fill(wins[wi].wx + wins[wi].ww - BORD, wins[wi].wy + TITLE, BORD,
		wins[wi].wh - TITLE, fc);
	fb::fill(wins[wi].wx, wins[wi].wy + wins[wi].wh - BORD, wins[wi].ww, BORD,
		fc);
	fb::fill(wins[wi].wx + BORD, wins[wi].wy + TITLE + BORD,
		wins[wi].ww - 2 * BORD, wins[wi].wh - TITLE - 2 * BORD, fb::WHITE);
	const tc = if (wi == focus) fb::WHITE else TITLEIDLE;
	fb::text(wins[wi].wx + 6, wins[wi].wy + 3, title_of(wi), tc, TITLEBG);
	for (let r = 0z; r < wins[wi].rows; r += 1) {
		line(wi, r);
	};
	draw_scrollbar(wi);
	if (wi == focus) {
		draw_tcursor(wi);
	};
};

fn draw_menu() void = {
	const mw = menu_w();
	const mh = menu_h();
	fb::fill(menu_x, menu_y, mw, mh, fb::WHITE);
	outline(menu_x, menu_y, mw, mh, fb::BLACK);
	for (let i = 0z; i < MI; i += 1) {
		const iy = menu_y + 4 + i * IH;
		const sel = (i: int) == menu_sel;
		const bg = if (sel) MENUSEL else fb::WHITE;
		const fg = if (sel) fb::WHITE else fb::BLACK;
		fb::fill(menu_x + 1, iy, mw - 2, IH, bg);
		fb::text(menu_x + 8, iy + 2, MITEMS[i], fg, bg);
	};
};

// Where the pointer is drawn. The art's own top left corner is the hotspot,
// so it goes straight onto the pointer position with nothing added or taken
// off, and the clamp keeps the whole 14x14 shape on the screen.
fn ptr_ox() size = mx;
fn ptr_oy() size = my;

fn ptr_lo_x() int = 0;
fn ptr_hi_x() int = (fb::width() - PW): int;
fn ptr_lo_y() int = 0;
fn ptr_hi_y() int = (fb::height() - PH): int;

// Paints the pointer from its art, one cell at a time. There is nothing to
// work out around the shape: the white edge and the black fill are both in
// the art already, so a cell that is 0 is simply left as it was.
fn draw_pointer() void = {
	const x = ptr_ox();
	const y = ptr_oy();
	for (let j = 0z; j < PH; j += 1) {
		for (let i = 0z; i < PW; i += 1) {
			const c = CUR[j * PW + i];
			if (c == CUR_EDGE) {
				fb::set(x + i, y + j, fb::WHITE);
			} else if (c == CUR_FILL) {
				fb::set(x + i, y + j, fb::BLACK);
			};
		};
	};
};

// Repaints one window into the shadow and presents only that rectangle. The
// desktop and every other window are already correct in the shadow, so there is
// nothing to redraw and nothing to copy.
fn repaint_win(wi: size) void = {
	if (wi == NONE || !wins[wi].used) {
		return;
	};
	hover = hovered();
	draw_window(wi);
	fb::present_rect(wins[wi].wx, wins[wi].wy, wins[wi].ww, wins[wi].wh);
};

// Repaints the desktop into the shadow and presents one whole frame.
fn repaint() void = {
	dirty_win = NONE;
	hover = hovered();
	fb::fill(0, 0, fb::width(), fb::height(), DESKTOP);
	for (let i = 0z; i < nz; i += 1) {
		draw_window(zlist[i]);
	};
	if (menu_open) {
		draw_menu();
	};
	draw_pointer();
	fb::present();
};

fn menu_w() size = {
	let n = 0z;
	for (let i = 0z; i < MI; i += 1) {
		const l = slen(MITEMS[i]);
		if (l > n) {
			n = l;
		};
	};
	return n * fb::CW + 16;
};

fn menu_h() size = MI * IH + 8;

fn menu_hit(x: size, y: size) int = {
	const mw = menu_w();
	const mh = menu_h();
	if (x < menu_x || x >= menu_x + mw || y < menu_y || y >= menu_y + mh) {
		return -1;
	};
	let rel = y - menu_y;
	if (rel < 4) {
		rel = 4;
	};
	const i = ((rel - 4) / IH): int;
	if (i < 0 || i >= (MI: int)) {
		return -1;
	};
	return i;
};

fn find_at(x: size, y: size) size = {
	let i = nz;
	for (i > 0) {
		i -= 1;
		const wi = zlist[i];
		const hh = if (wins[wi].hidden) TITLE else wins[wi].wh;
		if (x >= wins[wi].wx && x < wins[wi].wx + wins[wi].ww
				&& y >= wins[wi].wy && y < wins[wi].wy + hh) {
			return wi;
		};
	};
	return NONE;
};

fn edge_of(wi: size, x: size, y: size) u8 = {
	if (wins[wi].hidden) {
		return 0;
	};
	// A window over the whole screen has no frame left to grab: the button on
	// its title bar is the way back.
	if (wins[wi].full) {
		return 0;
	};
	if (x < wins[wi].wx || x >= wins[wi].wx + wins[wi].ww
			|| y < wins[wi].wy || y >= wins[wi].wy + wins[wi].wh) {
		return 0;
	};
	let e: u8 = 0;
	if (x < wins[wi].wx + EDGE) {
		e |= 1;
	};
	if (x + EDGE >= wins[wi].wx + wins[wi].ww) {
		e |= 2;
	};
	if (y < wins[wi].wy + EDGE) {
		e |= 4;
	};
	if (y + EDGE >= wins[wi].wy + wins[wi].wh) {
		e |= 8;
	};
	return e;
};

fn hovered() size = {
	const wi = find_at(mx, my);
	if (wi == NONE) {
		return NONE;
	};
	if (edge_of(wi, mx, my) != 0) {
		return wi;
	};
	return NONE;
};

fn raise(wi: size) void = {
	let k = 0z;
	for (let i = 0z; i < nz; i += 1) {
		if (zlist[i] != wi) {
			zlist[k] = zlist[i];
			k += 1;
		};
	};
	zlist[k] = wi;
	nz = k + 1;
};

fn blank(wi: size) void = {
	for (let i = 0z; i < HIST * MAXCOLS; i += 1) {
		bufs[base(wi) + i] = (' ': u8);
	};
};

// Set by the kernel. A terminal window is no use without something running in
// it, so making one asks for a shell to be started there.
export let new_win_hook: nullable *fn(wi: size) void = null;

// True while begin() is making the very first window, which must not ask for a
// shell because the kernel is already about to start one.
let booting = true;

fn new_window(x: size, y: size) void = {
	let wi = NONE;
	for (let i = 0z; i < MAXWIN; i += 1) {
		if (!wins[i].used) {
			wi = i;
			break;
		};
	};
	if (wi == NONE) {
		return;
	};
	wins[wi].used = true;
	wins[wi].hidden = false;
	wins[wi].cols = 80;
	wins[wi].rows = 22;
	layout(wi);
	const nx = clamp(x: int, (fb::width() - wins[wi].ww): int);
	const ny = clamp(y: int, (fb::height() - wins[wi].wh): int);
	wins[wi].wx = nx: size;
	wins[wi].wy = ny: size;
	wins[wi].total = 1;
	wins[wi].top = 0;
	wins[wi].crow = 0;
	wins[wi].ccol = 0;
	blank(wi);
	zlist[nz] = wi;
	nz += 1;
	focus = wi;
	fresh = true;
	if (!booting) {
		match (new_win_hook) {
		case null => void;
		case let f: *fn(wi: size) void =>
			f(wi);
		};
	};
};

fn delete_window(wi: size) void = {
	if (wi == NONE || !wins[wi].used) {
		return;
	};
	if (wins[wi].graphic) {
		gfree(wi);
	};
	wins[wi].graphic = false;
	wins[wi].used = false;
	let k = 0z;
	for (let i = 0z; i < nz; i += 1) {
		if (zlist[i] != wi) {
			zlist[k] = zlist[i];
			k += 1;
		};
	};
	nz = k;
	if (focus == wi) {
		focus = if (nz > 0) zlist[nz - 1] else NONE;
	};
};

fn hide_window(wi: size) void = {
	if (wi == NONE) {
		return;
	};
	wins[wi].hidden = !wins[wi].hidden;
	if (wins[wi].hidden) {
		if (focus == wi) {
			focus = top_visible();
		};
	} else {
		raise(wi);
		focus = wi;
	};
};

fn top_visible() size = {
	let i = nz;
	for (i > 0) {
		i -= 1;
		const wi = zlist[i];
		if (wins[wi].used && !wins[wi].hidden) {
			return wi;
		};
	};
	return NONE;
};

fn scroll_buffer(wi: size) void = {
	const b = base(wi);
	for (let i = 0z; i < (HIST - 1) * MAXCOLS; i += 1) {
		bufs[b + i] = bufs[b + i + MAXCOLS];
	};
	for (let c = 0z; c < MAXCOLS; c += 1) {
		bufs[b + (HIST - 1) * MAXCOLS + c] = (' ': u8);
	};
	wins[wi].crow = HIST - 1;
	if (wins[wi].top > 0) {
		wins[wi].top -= 1;
	};
};

fn follow(wi: size) void = {
	if (wins[wi].crow >= wins[wi].top
			&& wins[wi].crow < wins[wi].top + wins[wi].rows) {
		return;
	};
	if (wins[wi].crow >= wins[wi].rows) {
		wins[wi].top = wins[wi].crow - wins[wi].rows + 1;
	} else {
		wins[wi].top = 0;
	};
	if (wins[wi].top + wins[wi].rows > HIST) {
		wins[wi].top = HIST - wins[wi].rows;
	};
};

fn scroll_to(wi: size, y: size) void = {
	if (wins[wi].total <= wins[wi].rows) {
		return;
	};
	const sh = wins[wi].rows * fb::CH;
	let th = sh * wins[wi].rows / wins[wi].total;
	if (th < 20) {
		th = 20;
	};
	if (th > sh) {
		th = sh;
	};
	const span = sh - th;
	if (span == 0) {
		return;
	};
	let rel: size = if (y > sby(wi)) y - sby(wi) else 0;
	if (rel < th / 2z) {
		rel = th / 2z;
	};
	if (rel > span + th / 2z) {
		rel = span + th / 2z;
	};
	wins[wi].top = (rel - th / 2z) * (wins[wi].total - wins[wi].rows) / span;
};

fn on_scrollbar(wi: size, x: size, y: size) bool = {
	if (wins[wi].graphic) {
		return false;
	};
	return x >= sbx(wi) && x < sbx(wi) + SB
		&& y >= sby(wi) && y < sby(wi) + wins[wi].rows * fb::CH;
};

fn begin_move(wi: size, x: size, y: size) void = {
	grab = 1;
	gwin = wi;
	gox = x - wins[wi].wx;
	goy = y - wins[wi].wy;
};

fn begin_resize(wi: size, e: u8) void = {
	grab = 2;
	gwin = wi;
	gedge = e;
	gwx = wins[wi].wx;
	gwy = wins[wi].wy;
	gww = wins[wi].ww;
	gwh = wins[wi].wh;
	// The size follows the pointer from wherever the grab began. Taking the
	// pointer's absolute position instead would make the window jump as soon
	// as the button went down, because an edge is grabbed a pixel or two
	// inside the frame and the size would snap to that.
	grx = mx;
	gry = my;
};

fn move_drag() void = {
	const wi = gwin;
	if (wi == NONE || !wins[wi].used) {
		grab = 0;
		return;
	};
	const nx = clamp((mx: int) - (gox: int), (fb::width() - wins[wi].ww): int);
	const ny = clamp((my: int) - (goy: int), (fb::height() - wins[wi].wh): int);
	wins[wi].wx = nx: size;
	wins[wi].wy = ny: size;
};

fn apply_size(wi: size, nc: size, nr: size, nwx: size, nwy: size) void = {
	wins[wi].cols = nc;
	wins[wi].rows = nr;
	layout(wi);
	wins[wi].wx = nwx;
	wins[wi].wy = nwy;
	// The view was at most (total - rows) lines down, but rows just changed.
	// A taller window makes that bound smaller than where the view still
	// sits, and the scrollbar would then place its thumb past the end of
	// the track, outside the window. Pull the view back inside the buffer
	// before anything is drawn.
	if (wins[wi].total > wins[wi].rows) {
		if (wins[wi].top > wins[wi].total - wins[wi].rows) {
			wins[wi].top = wins[wi].total - wins[wi].rows;
		};
	} else {
		wins[wi].top = 0;
	};
	if (wins[wi].top + wins[wi].rows > HIST) {
		wins[wi].top = if (HIST > wins[wi].rows) HIST - wins[wi].rows else 0;
	};
	if (wins[wi].crow >= HIST) {
		wins[wi].crow = HIST - 1;
	};
};

// Resizes from the grabbed frame edge; the opposite edges stay put, and the
// result snaps to whole character cells.
fn resize_drag() void = {
	const wi = gwin;
	if (wi == NONE || !wins[wi].used) {
		grab = 0;
		return;
	};
	if (wins[wi].graphic) {
		resize_gfx(wi);
		return;
	};
	const cw = (fb::CW: int);
	const ch = (fb::CH: int);
	const bd = ((2 * BORD): int);
	const sbi = (SB: int);
	const minw = (MINCOLS: int) * cw + bd + sbi;
	const minh = (TITLE: int) + bd + (MINROWS: int) * ch;
	const px = mx: int;
	const py = my: int;
	const rx1 = (gwx + gww): int;
	const ry1 = (gwy + gwh): int;
	// Each edge follows the pointer by how far it has moved since the grab,
	// so pressing on an edge does not resize anything on its own.
	let nww = gww: int;
	let nwh = gwh: int;
	if ((gedge & 1) != 0) {
		nww = (gww: int) - (px - (grx: int));
	};
	if ((gedge & 2) != 0) {
		nww = (gww: int) + (px - (grx: int));
	};
	if ((gedge & 4) != 0) {
		nwh = (gwh: int) - (py - (gry: int));
	};
	if ((gedge & 8) != 0) {
		nwh = (gwh: int) + (py - (gry: int));
	};
	if (nww < minw) {
		nww = minw;
	};
	if (nwh < minh) {
		nwh = minh;
	};
	const nc = ((nww - bd - sbi) / cw): size;
	const nr = ((nwh - (TITLE: int) - bd) / ch): size;
	const fww = (nc: int) * cw + bd + sbi;
	const fwh = (nr: int) * ch + (TITLE: int) + bd;
	let nwx = gwx: int;
	let nwy = gwy: int;
	if ((gedge & 1) != 0) {
		nwx = rx1 - fww;
	};
	if ((gedge & 4) != 0) {
		nwy = ry1 - fwh;
	};
	if (nwx + fww > (fb::width(): int)) {
		nwx = (fb::width(): int) - fww;
	};
	if (nwy + fwh > (fb::height(): int)) {
		nwy = (fb::height(): int) - fwh;
	};
	if (nwx < 0) {
		nwx = 0;
	};
	if (nwy < 0) {
		nwy = 0;
	};
	if (nc == wins[wi].cols && nr == wins[wi].rows
			&& (nwx: size) == wins[wi].wx && (nwy: size) == wins[wi].wy) {
		return;
	};
	apply_size(wi, nc, nr, nwx: size, nwy: size);
};

// Resizes a drawing window by whole pixels instead of character cells: what
// counts is how much picture fits, and a game's picture is not a multiple of
// any letter's width. The frame keeps its frame, the opposite edges stay put,
// and the picture is made to fit whatever is left.
fn resize_gfx(wi: size) void = {
	const bd = ((2 * BORD): int);
	const tb = ((TITLE + 2 * BORD): int);
	const px = mx: int;
	const py = my: int;
	const rx1 = (gwx + gww): int;
	const ry1 = (gwy + gwh): int;
	let nww = gww: int;
	let nwh = gwh: int;
	if ((gedge & 1) != 0) {
		nww = (gww: int) - (px - (grx: int));
	};
	if ((gedge & 2) != 0) {
		nww = (gww: int) + (px - (grx: int));
	};
	if ((gedge & 4) != 0) {
		nwh = (gwh: int) - (py - (gry: int));
	};
	if ((gedge & 8) != 0) {
		nwh = (gwh: int) + (py - (gry: int));
	};
	// Small enough to be useless as a window is not worth having.
	if (nww < bd + 64) {
		nww = bd + 64;
	};
	if (nwh < tb + 48) {
		nwh = tb + 48;
	};
	let nwx = gwx: int;
	let nwy = gwy: int;
	if ((gedge & 1) != 0) {
		nwx = rx1 - nww;
	};
	if ((gedge & 4) != 0) {
		nwy = ry1 - nwh;
	};
	if (nwx + nww > (fb::width(): int)) {
		nwx = (fb::width(): int) - nww;
	};
	if (nwy + nwh > (fb::height(): int)) {
		nwy = (fb::height(): int) - nwh;
	};
	if (nwx < 0) {
		nwx = 0;
	};
	if (nwy < 0) {
		nwy = 0;
	};
	if (nww == (gww: int) && nwh == (gwh: int)
			&& (nwx: size) == gwx && (nwy: size) == gwy) {
		return;
	};
	const nw = (nww: size) - 2 * BORD;
	const nh = (nwh: size) - TITLE - 2 * BORD;
	// The picture first: if there is no room for it the window keeps the size
	// it already has, rather than ending up a frame around nothing.
	if (!galloc(wi, nw, nh)) {
		return;
	};
	wins[wi].wx = nwx: size;
	wins[wi].wy = nwy: size;
	wins[wi].ww = nww: size;
	wins[wi].wh = nwh: size;
};

fn open_menu(which: u8) void = {
	const mw = menu_w();
	const mh = menu_h();
	menu_x = clamp(mx: int, (fb::width() - mw): int): size;
	menu_y = clamp(my: int, (fb::height() - mh): int): size;
	menu_btn = which;
	menu_win = find_at(mx, my);
	menu_open = true;
	menu_sel = menu_hit(mx, my);
};

fn menu_activate(sel: int) void = {
	const wi = menu_win;
	if (sel == 0) {
		new_window(mx, my);
	} else if (sel == 1) {
		if (wi == NONE) {
			return;
		};
		raise(wi);
		focus = wi;
		// Resizing starts from where the window really is, so a window that
		// was over the whole screen comes back to its own size first.
		if (wins[wi].graphic) {
			set_full(wi, false);
		};
		fmode = 2;
		gwin = wi;
		gedge = 2 | 8;
		gwx = wins[wi].wx;
		gwy = wins[wi].wy;
		gww = wins[wi].ww;
		gwh = wins[wi].wh;
		grx = mx;
		gry = my;
	} else if (sel == 2) {
		if (wi == NONE) {
			return;
		};
		raise(wi);
		focus = wi;
		if (wins[wi].graphic) {
			set_full(wi, false);
		};
		fmode = 1;
		gwin = wi;
		gox = mx - wins[wi].wx;
		goy = my - wins[wi].wy;
	} else if (sel == 3) {
		delete_window(wi);
	} else if (sel == 4) {
		hide_window(wi);
	} else if (sel == 5) {
		rt::halt();
	};
};

fn press1(x: size, y: size) void = {
	const wi = find_at(x, y);
	if (wi == NONE) {
		return;
	};
	raise(wi);
	focus = wi;
	if (wins[wi].hidden) {
		wins[wi].hidden = false;
		return;
	};
	// The square on the title bar of a drawing window, before anything else
	// that lives up there: it grows the window over the whole screen or puts
	// it back where it was.
	if (wins[wi].graphic && over_btn(wi, x, y)) {
		set_full(wi, !wins[wi].full);
		return;
	};
	if (on_scrollbar(wi, x, y)) {
		sbdrag = true;
		sbwin = wi;
		scroll_to(wi, y);
		return;
	};
	const e = edge_of(wi, x, y);
	if (e != 0) {
		begin_resize(wi, e);
		return;
	};
	if (y < wins[wi].wy + TITLE) {
		begin_move(wi, x, y);
	};
};

// Where a mouse event belongs: the drawing program when the pointer is on its
// picture and no gesture of the desktop's is in the way, the desktop in every
// other case. The motion in the answer is what the program should see, and
// that is none of it when the pointer has wandered off the picture with a
// button still down - a program that turns with the mouse must not turn
// because the pointer was crossing a title bar.
export type route = struct {
	app: bool,
	dx: int,
	dy: int,
};

// Consumes the mouse deltas and button state, and says who they were for.
export fn mouse(dx: int, dy: int, btn: u8) route = {
	if (!on) {
		// There is no desktop to give the event to, so whoever is drawing at
		// the screen is the only one who can want it.
		return route { app = true, dx = dx, dy = dy };
	};
	mx = clampv((mx: int) + dx, ptr_lo_x(), ptr_hi_x()): size;
	my = clampv((my: int) + dy, ptr_lo_y(), ptr_hi_y()): size;

	const b1 = (btn & 1u8) != 0;
	const w1 = (lastbtn & 1u8) != 0;
	const b2 = (btn & 2u8) != 0;
	const w2 = (lastbtn & 2u8) != 0;
	const b3 = (btn & 4u8) != 0;
	const w3 = (lastbtn & 4u8) != 0;

	// Is the pointer on the picture of the drawing window that has the focus?
	// That, with nothing else in the way, is what makes this the program's.
	let here = false;
	if (!menu_open && grab == 0 && fmode == 0 && !sbdrag) {
		const g = focus;
		here = g != NONE && g < MAXWIN && wins[g].used && wins[g].graphic
			&& !wins[g].hidden && find_at(mx, my) == g
			&& over_content(g, mx, my);
	};
	// A button pressed on the picture stays the program's until it comes up,
	// so the release always reaches the program even if the pointer has left
	// the window by then: losing it would leave the game firing forever.
	let app = here;
	if (here) {
		appbtn = btn;
	} else if ((appbtn & btn) != appbtn) {
		app = true;
	};
	const mdx = if (here) dx else 0;
	const mdy = if (here) dy else 0;
	appbtn = appbtn & btn;

	if (menu_open) {
		menu_sel = menu_hit(mx, my);
		const held = if (menu_btn == 2u8) b2 else b3;
		if (!held) {
			const sel = menu_sel;
			menu_open = false;
			menu_sel = -1;
			if (sel >= 0) {
				menu_activate(sel);
			};
		};
	} else if (here) {
		// The picture belongs to the program: its buttons are not the
		// desktop's to act on, and its window is already at hand.
		void;
	} else if (b3 && !w3) {
		open_menu(4u8);
	} else if (b2 && !w2) {
		open_menu(2u8);
	} else if (fmode != 0) {
		if (b1 && !w1) {
			fmode = 0;
		} else if (fmode == 1) {
			move_drag();
		} else {
			resize_drag();
		};
	} else {
		if (b1 && !w1) {
			press1(mx, my);
		};
		if (!b1 && w1) {
			grab = 0;
			sbdrag = false;
		};
		if (grab == 1) {
			move_drag();
		} else if (grab == 2) {
			resize_drag();
		} else if (sbdrag && b1) {
			scroll_to(sbwin, my);
		};
	};

	lastbtn = btn;
	repaint();
	return route { app = app, dx = mdx, dy = mdy };
};

// An escape sequence arrives one byte at a time and only means something once it
// has been put back together. A terminal window that understands CSI can be
// drawn on directly, which is what a full-screen program such as an editor
// needs: it moves the cursor and clears lines rather than scrolling.
let csi_state: int = 0;		// 0 plain text, 1 saw ESC, 2 collecting a CSI
let csi_param: [16]u8 = [0...];
let csi_n: size = 0;

fn csi_number(final: u8) void = {
	const wi = out_target();
	if (wi == NONE || !wins[wi].used) {
		return;
	};
	let a = 0z;
	let b = 0z;
	let seen = 0;
	for (let i = 0z; i < csi_n; i += 1) {
		const c = csi_param[i];
		if (c == (';': u8)) {
			seen += 1;
			continue;
		};
		if (seen == 0) {
			a = a * 10 + (c - ('0': u8));
		} else {
			b = b * 10 + (c - ('0': u8));
		};
	};
	if (final == ('H': u8) || final == ('f': u8)) {
		// Cursor position, counted from one, and a missing number means one.
		let r: size = if (a > 0) a - 1 else 0;
		let c: size = if (b > 0) b - 1 else 0;
		if (r >= HIST) {
			r = HIST - 1;
		};
		if (c >= wins[wi].cols) {
			c = wins[wi].cols - 1;
		};
		wins[wi].crow = r;
		wins[wi].ccol = c;
		if (wins[wi].crow + 1 > wins[wi].total) {
			wins[wi].total = wins[wi].crow + 1;
		};
		follow(wi);
	} else if (final == ('J': u8)) {
		if (a == 2) {
			clear_window(wi);
		} else {
			erase_display(wi, wins[wi].crow, wins[wi].ccol);
		};
	} else if (final == ('K': u8)) {
		erase_display(wi, wins[wi].crow, wins[wi].ccol);
	} else if (final == ('A': u8)) {
		if (wins[wi].crow > 0) {
			wins[wi].crow -= 1;
		};
	} else if (final == ('B': u8)) {
		if (wins[wi].crow + 1 < HIST) {
			wins[wi].crow += 1;
		};
	} else if (final == ('C': u8)) {
		if (wins[wi].ccol + 1 < wins[wi].cols) {
			wins[wi].ccol += 1;
		};
	} else if (final == ('D': u8)) {
		if (wins[wi].ccol > 0) {
			wins[wi].ccol -= 1;
		};
	};
};

// Blanks a run of the window's text buffer.
fn erase_range(wi: size, from: size, to: size) void = {
	if (to > HIST * MAXCOLS) {
		to = HIST * MAXCOLS;
	};
	for (let i = from; i < to; i += 1) {
		bufs[i] = (' ': u8);
	};
};

// Blanks from a position to the end of that line.
fn erase_display(wi: size, li: size, col: size) void = {
	if (li >= HIST) {
		return;
	};
	erase_range(wi, at(wi, li, col), at(wi, li, wins[wi].cols));
};

fn clear_window(wi: size) void = {
	blank(wi);
	wins[wi].crow = 0;
	wins[wi].ccol = 0;
	wins[wi].top = 0;
	wins[wi].total = 1;
};

// Draws one cell of a window into the shadow and pushes only that cell onto
// the card. A character shows up the moment it is written, the way a terminal
// shows it, without copying the whole screen for every letter.
fn put_cell(wi: size, li: size, col: size, cursor: bool) void = {
	if (li < wins[wi].top || li >= wins[wi].top + wins[wi].rows) {
		return;
	};
	if (col >= wins[wi].cols) {
		return;
	};
	const ch = bufs[at(wi, li, col)];
	const x = wins[wi].wx + BORD + col * fb::CW;
	const y = wins[wi].wy + TITLE + BORD + (li - wins[wi].top) * fb::CH;
	if (cursor) {
		fb::cell(x, y, ch, fb::WHITE, fb::BLACK);
	} else {
		fb::cell(x, y, ch, fb::BLACK, fb::WHITE);
	};
	fb::present_rect(x, y, fb::CW, fb::CH);
};

// Where the cursor block is currently painted, so it can be lifted off the
// cell it was sitting on before the cursor moves.
let cur_painted = false;
let cur_li: size = 0;
let cur_col: size = 0;

export fn putc(ch: u8) void = {
	if (!on) {
		return;
	};
	const wi = out_target();
	if (wi == NONE || !wins[wi].used) {
		return;
	};
	if (csi_state == 1) {
		csi_state = 0;
		if (ch == ('[': u8)) {
			csi_state = 2;
			csi_n = 0;
		};
		return;
	};
	if (csi_state == 2) {
		if ((ch >= ('0': u8) && ch <= ('9': u8)) || ch == (';': u8)) {
			if (csi_n < len(csi_param)) {
				csi_param[csi_n] = ch;
				csi_n += 1;
			};
			return;
		};
		csi_state = 0;
		csi_number(ch);
		cur_painted = false;
		dirty_win = wi;
		return;
	};
	if (ch == 0x1B) {
		csi_state = 1;
		return;
	};
	const was_top = wins[wi].top;
	let wrote = false;
	let wli = 0z;
	let wcl = 0z;
	if (ch == ('\n': u8)) {
		wins[wi].crow += 1;
		wins[wi].ccol = 0;
		if (wins[wi].crow >= HIST) {
			scroll_buffer(wi);
		};
	} else if (ch == ('\r': u8)) {
		wins[wi].ccol = 0;
	} else if (ch == ('\b': u8)) {
		if (wins[wi].ccol > 0) {
			wins[wi].ccol -= 1;
		} else if (wins[wi].crow > 0) {
			wins[wi].crow -= 1;
			wins[wi].ccol = wins[wi].cols - 1;
		};
	} else {
		wli = wins[wi].crow;
		wcl = wins[wi].ccol;
		bufs[at(wi, wli, wcl)] = ch;
		wrote = true;
		wins[wi].ccol += 1;
		if (wins[wi].ccol >= wins[wi].cols) {
			wins[wi].ccol = 0;
			wins[wi].crow += 1;
			if (wins[wi].crow >= HIST) {
				scroll_buffer(wi);
			};
		};
	};
	if (wins[wi].crow + 1 > wins[wi].total) {
		wins[wi].total = wins[wi].crow + 1;
		if (wins[wi].total > HIST) {
			wins[wi].total = HIST;
		};
	};
	follow(wi);
	if (wins[wi].top != was_top) {
		// The window scrolled, so everything in it moved: redraw it whole.
		cur_painted = false;
		dirty_win = wi;
		return;
	};
	// Lift the cursor off the cell it was painted on, show the character, and
	// put the cursor where it now belongs.
	if (cur_painted) {
		put_cell(wi, cur_li, cur_col, false);
	};
	if (wrote) {
		put_cell(wi, wli, wcl, false);
	};
	cur_li = wins[wi].crow;
	cur_col = wins[wi].ccol;
	put_cell(wi, cur_li, cur_col, true);
	cur_painted = true;
};

// The size of the focused window, so a full-screen program can lay itself out
// to the screen Bunix actually has. The window is smaller than the display
// behind it, and reporting the display's size instead would push the bottom of
// the program off the bottom of the window.
export fn screen_rows() size = {
	if (!on || focus == NONE || !wins[focus].used || wins[focus].graphic) {
		return 0;
	};
	return wins[focus].rows;
};

export fn screen_cols() size = {
	if (!on || focus == NONE || !wins[focus].used || wins[focus].graphic) {
		return 0;
	};
	return wins[focus].cols;
};

// Draws any terminal output written since the last frame. The kernel calls this
// once per scheduling slice, so a program that prints a whole line pays for one
// repaint rather than one per character.
export fn sync() void = {
	if (dirty_win != NONE) {
		const wi = dirty_win;
		dirty_win = NONE;
		repaint_win(wi);
	};
};

export fn begin() void = {
	if (!fb::active()) {
		return;
	};
	on = true;
	nz = 0;
	focus = NONE;
	grab = 0;
	fmode = 0;
	menu_open = false;
	sbdrag = false;
	for (let i = 0z; i < MAXWIN; i += 1) {
		if (wins[i].graphic && wins[i].gbuf != 0) {
			gfree(i);
		};
		wins[i].graphic = false;
		wins[i].used = false;
	};
	appbtn = 0;
	const ww = 80 * fb::CW + 2 * BORD + SB;
	const wh = TITLE + 2 * BORD + 22 * fb::CH;
	mx = fb::width() / 2;
	my = fb::height() / 2;
	booting = true;
	new_window((fb::width() - ww) / 2, (fb::height() - wh) / 2);
	booting = false;
	fresh = false;		// the shell prints the first prompt itself
	repaint();
};
