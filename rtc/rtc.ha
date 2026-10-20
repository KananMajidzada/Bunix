use architecture;

// The battery-backed clock on the motherboard, read over the CMOS ports.
//
// Nothing in the kernel timer needs this: that counts from boot and cannot go
// backwards, which is all a timer has to do. What is missing without it is any
// idea what the date is, which is the first thing a person asks a machine and
// the last thing this one could answer. The chip has been keeping the time
// while the power was off, and it is two ports away.

const INDEX: u16 = 0x70;
const DATA: u16 = 0x71;

// Where each field sits in the bank of registers.
const SEC: u8 = 0x00;
const MIN: u8 = 0x02;
const HOUR: u8 = 0x04;
const WDAY: u8 = 0x06;
const MDAY: u8 = 0x07;
const MONTH: u8 = 0x08;
const YEAR: u8 = 0x09;
const STATA: u8 = 0x0A;
const STATB: u8 = 0x0B;

// Status A, bit 7: the counters are being updated right now.
const UPDATING: u8 = 0x80;
// Status B, bit 1: the hours are counted from zero rather than from one, and
// bit 2: they are plain binary rather than coded decimal.
const HOURS24: u8 = 0x02;
const BINARY: u8 = 0x04;

export type clock = struct {
	year: u64,
	month: u8,
	mday: u8,
	hour: u8,
	minute: u8,
	second: u8,
	// The chip counts the days from one, with Sunday as one and Saturday as
	// seven. Left as it is read rather than shifted, so that what a program
	// is told is what the chip said.
	wday: u8,
};

type raw = struct {
	year: u8,
	month: u8,
	mday: u8,
	hour: u8,
	minute: u8,
	second: u8,
	wday: u8,
};

fn reg(n: u8) u8 = {
	architecture::outb(INDEX, n);
	return architecture::inb(DATA);
};

// The counters are kept in binary coded decimal on the common chips, so 0x59
// is fifty-nine and not eighty-nine. A chip set to binary marks its values
// with the high bit, which is how the two are told apart.
fn decode(v: u8, binary: bool) u8 = {
	if (binary) {
		return v & 0x7f;
	};
	return (v & 0x0f) + (v >> 4) * 10;
};

fn grab(binary: bool) raw = {
	return raw {
		year = decode(reg(YEAR), binary),
		month = decode(reg(MONTH), binary),
		mday = decode(reg(MDAY), binary),
		hour = decode(reg(HOUR), binary),
		minute = decode(reg(MIN), binary),
		second = decode(reg(SEC), binary),
		wday = decode(reg(WDAY), binary),
	};
};

// The clock is left alone for a moment every second while it rolls its
// counters over, and a read that lands in that moment gets the end of one
// second and the start of the next. Waiting for the flag that says so costs
// nothing, since reading all seven registers takes far less time than the
// update it is waiting for.
fn settled() void = {
	for (let i = 0u64; i < 100000; i += 1) {
		if ((reg(STATA) & UPDATING) == 0) {
			return;
		};
		architecture::pause();
	};
};

fn same(a: raw, b: raw) bool = {
	return a.year == b.year && a.month == b.month && a.mday == b.mday
		&& a.hour == b.hour && a.minute == b.minute && a.second == b.second;
};

// Whether the clock is there at all. A machine without one leaves every
// register reading 0xff, which is a year of 165 and a day of 51.
export fn present() bool = {
	const b = reg(STATB);
	return b != 0xFF;
};

export fn now() clock = {
	const flags = reg(STATB);
	const binary = (flags & BINARY) != 0;
	const h24 = (flags & HOURS24) != 0;

	settled();
	let r = grab(binary);
	settled();
	const again = grab(binary);
	if (!same(r, again)) {
		// The clock rolled its counters over between the two reads, so one of
		// them was taken across the boundary and neither of them is a whole
		// second. The later reading is the one worth keeping.
		settled();
		r = grab(binary);
	};

	// The chip keeps two digits of the year. Which century those two sit in
	// is not recorded anywhere, and the only guess that has been right for
	// longer than this has been written down is that a year below 70 is this
	// century and anything else is the one before it.
	const two = r.year;
	const year = if (two < 70) 2000 + (two: u64) else 1900 + (two: u64);

	// A chip counting from one in twelve hour mode stores thirteen where a
	// person means one.
	let hour = r.hour;
	if (!h24) {
		const pm = (flags & 0x01) != 0;
		if (hour == 12) {
			hour = 12;
		} else if (pm) {
			hour += 12;
		};
	};

	return clock {
		year = year,
		month = r.month,
		mday = r.mday,
		hour = hour,
		minute = r.minute,
		second = r.second,
		wday = r.wday,
	};
};

// Days from the start of the year to the day in question. The leap year is the
// one rule that has never once been amended.
fn yearday(c: clock) u64 = {
	const LEN: [12]u64 = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	const leap = leapyear(c.year);
	let n: u64 = 0;
	for (let i = 0z; i + 1 < (c.month: size) && i < 12; i += 1) {
		n += LEN[i];
		if (i == 1 && leap) {
			n += 1;
		};
	};
	return n + (c.mday: u64) - 1;
};

fn leapyear(y: u64) bool = {
	return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
};

fn daysfromyear(y: u64) u64 = {
	// The days in each year from 1970 up to this one. 1970 is the year the
	// epoch was defined against, and it is a year nobody chose for its date.
	let n: u64 = 0;
	for (let i = 1970u64; i < y; i += 1) {
		n += if (leapyear(i)) 366 else 365;
	};
	return n;
};

// Seconds since the start of 1970, the number everything else is measured
// against. It is derived from the date rather than kept anywhere, so it cannot
// be anywhere near the day the clock is reading.
export fn epoch(c: clock) u64 = {
	return daysfromyear(c.year) * 86400 + yearday(c) * 86400
		+ (c.hour: u64) * 3600 + (c.minute: u64) * 60 + (c.second: u64);
};