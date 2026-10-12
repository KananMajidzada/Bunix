use fb;
use rt;

// kit: the window manager the machine boots into. A plain desktop holds
// terminals drawn as flat rectangles: a title bar to drag, a frame that turns
// black under the pointer so an edge can be grabbed to resize, and a scrollbar
// on the right edge. Button 1 selects, moves, and resizes; buttons 2 and 3
// raise a menu. Window changes repaint the whole desktop into the framebuffer
// shadow, so moving or resizing never leaves a trail behind. Terminal output
// is instead batched: writes mark the screen dirty and one frame is drawn when
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

const MITEMS: [6]str = ["new", "resize", "move", "delete", "hide", "exit"];

// Pointer: classic arrow cursor (tip at hotspot). 14x14 body stored as
// art: '#' = black arrow, '.' = white halo. 196 cells total.
const CUR: [196]u8 = [
	0x23,0x23,0x23,0x23,0x23,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x23,0x23,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x23,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x23,0x23,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x23,0x23,0x2e,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x23,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,0x2e,
	0x23,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,0x2e,0x2e,0x2e,
	0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,0x2e,0x2e,
	0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,0x2e,
	0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,
	0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,0x2e,
	0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,0x23,
	0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x2e,0x23,0x23,
];
def BW: size = 18;
def BH: size = 18;

type win = struct {
	used: bool,
	hidden: bool,
	wx: size, wy: size, ww: size, wh: size,
	cols: size, rows: size,
	total: size, top: size, crow: size, ccol: size,
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

let grab: u8 = 0;	// 1 move, 2 resize, held with button 1
let gwin: size = NONE;
let gedge: u8 = 0;
let gox = 0z;
let goy = 0z;
let gwx = 0z;
let gwy = 0z;
let gww = 0z;
let gwh = 0z;
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
let dirty = false;

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
		const ty = if (span > 0) sby(wi) + span * wins[wi].top / maxtop
			else sby(wi);
		fb::fill(sbx(wi) + 1, ty, SB - 2, th, THUMB);
	};
};

fn draw_shade(wi: size) void = {
	const fc = if (hover == wi) FRAMEHI else FRAME;
	fb::fill(wins[wi].wx, wins[wi].wy, wins[wi].ww, TITLE, TITLEBG);
	fb::fill(wins[wi].wx, wins[wi].wy + TITLE - BORD, wins[wi].ww, BORD, fc);
	fb::text(wins[wi].wx + 6, wins[wi].wy + 3, "term", TITLEIDLE, TITLEBG);
};

fn draw_window(wi: size) void = {
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
	fb::text(wins[wi].wx + 6, wins[wi].wy + 3, "term", tc, TITLEBG);
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

fn ptr_ox() size = mx - 2;
fn ptr_oy() size = my - 2;

fn ptr_lo_x() int = 2;
fn ptr_hi_x() int = (fb::width() - 2): int;
fn ptr_lo_y() int = 2;
fn ptr_hi_y() int = (fb::height() - 2): int;

fn body(i: size, j: size) bool = {
	if (i < 2 || j < 2 || i + 2 >= BW || j + 2 >= BH) {
		return false;
	};
	return CUR[(j - 2) * 14 + (i - 2)] == 0x23;
};

fn draw_pointer() void = {
	const x = ptr_ox();
	const y = ptr_oy();
	for (let j = 0z; j < BH; j += 1) {
		for (let i = 0z; i < BW; i += 1) {
			if (body(i, j)) {
				fb::set(x + i, y + j, fb::BLACK);
			};
		};
	};
	for (let j = 0z; j < BH; j += 1) {
		for (let i = 0z; i < BW; i += 1) {
			if (body(i, j)) {
				continue;
			};
			let edge = false;
			if (i > 0 && body(i - 1, j)) {
				edge = true;
			};
			if (i + 1 < BW && body(i + 1, j)) {
				edge = true;
			};
			if (j > 0 && body(i, j - 1)) {
				edge = true;
			};
			if (j + 1 < BH && body(i, j + 1)) {
				edge = true;
			};
			if (edge) {
				fb::set(x + i, y + j, fb::WHITE);
			};
		};
	};
};

// Repaints the desktop into the shadow and presents one whole frame.
fn repaint() void = {
	dirty = false;
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
};

fn delete_window(wi: size) void = {
	if (wi == NONE || !wins[wi].used) {
		return;
	};
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
	let nww = gww: int;
	let nwh = gwh: int;
	if ((gedge & 1) != 0) {
		nww = rx1 - px;
	};
	if ((gedge & 2) != 0) {
		nww = px - (gwx: int);
	};
	if ((gedge & 4) != 0) {
		nwh = ry1 - py;
	};
	if ((gedge & 8) != 0) {
		nwh = py - (gwy: int);
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
		fmode = 2;
		gwin = wi;
		gedge = 2 | 8;
		gwx = wins[wi].wx;
		gwy = wins[wi].wy;
		gww = wins[wi].ww;
		gwh = wins[wi].wh;
	} else if (sel == 2) {
		if (wi == NONE) {
			return;
		};
		raise(wi);
		focus = wi;
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

// Consumes the mouse deltas and button state.
export fn mouse(dx: int, dy: int, btn: u8) void = {
	if (!on) {
		return;
	};
	mx = clampv((mx: int) + dx, ptr_lo_x(), ptr_hi_x()): size;
	my = clampv((my: int) + dy, ptr_lo_y(), ptr_hi_y()): size;

	const b1 = (btn & 1u8) != 0;
	const w1 = (lastbtn & 1u8) != 0;
	const b2 = (btn & 2u8) != 0;
	const w2 = (lastbtn & 2u8) != 0;
	const b3 = (btn & 4u8) != 0;
	const w3 = (lastbtn & 4u8) != 0;

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
};

export fn putc(ch: u8) void = {
	if (!on) {
		return;
	};
	const wi = focus;
	if (wi == NONE || !wins[wi].used) {
		return;
	};
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
		bufs[at(wi, wins[wi].crow, wins[wi].ccol)] = ch;
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
	dirty = true;
};

// Draws any terminal output written since the last frame.
export fn sync() void = {
	if (dirty) {
		repaint();
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
		wins[i].used = false;
	};
	const ww = 80 * fb::CW + 2 * BORD + SB;
	const wh = TITLE + 2 * BORD + 22 * fb::CH;
	mx = fb::width() / 2;
	my = fb::height() / 2;
	new_window((fb::width() - ww) / 2, (fb::height() - wh) / 2);
	fresh = false;		// the shell prints the first prompt itself
	repaint();
};
