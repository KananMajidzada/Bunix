use lib;
use rt;

// date [+%FORMAT]
//
// The date and the time, read from the clock on the motherboard. That is the
// same chip that kept the time while the machine was off, so this is the real
// date and not a count of seconds since boot.
//
// A format is a run of text with % codes in it, the way strftime writes one.
// What is here is the part anyone actually uses: %Y the year, %m the month, %d
// the day, %H the hour, %M the minute, %S the second, %a the day of the week,
// %b the month by name, %s the seconds since 1970, %F and %T for the usual
// pairs, and %% for a percent of its own. Anything else is copied out as it
// stands rather than swallowed.

const DAYS: [7]str = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS: [12]str = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

let year: u64 = 0;
let month: u64 = 1;
let day: u64 = 1;
let hour: u64 = 0;
let minute: u64 = 0;
let second: u64 = 0;
let wday: u64 = 1;
let epoch: u64 = 0;

fn rtcfile() []u8 = {
	return *(&"/proc/rtc": *[]u8);
};

// One line of the file, which is a field name and its value.
fn absorb(line: []u8) bool = {
	const sp = lib::first_space(line);
	if (sp >= len(line)) {
		return true;
	};
	const name = line[..sp];
	const v = lib::parse_int(line[sp + 1..], 0);
	if (lib::eq_str(name, "year")) {
		year = v;
	} else if (lib::eq_str(name, "month")) {
		month = v;
	} else if (lib::eq_str(name, "day")) {
		day = v;
	} else if (lib::eq_str(name, "hour")) {
		hour = v;
	} else if (lib::eq_str(name, "minute")) {
		minute = v;
	} else if (lib::eq_str(name, "second")) {
		second = v;
	} else if (lib::eq_str(name, "weekday")) {
		wday = v;
	} else if (lib::eq_str(name, "epoch")) {
		epoch = v;
	};
	return true;
};

fn read_clock() bool = {
	const text = lib::slurp(rtcfile());
	if (len(text) == 0) {
		return false;
	};
	year = 0;
	month = 1;
	day = 1;
	hour = 0;
	minute = 0;
	second = 0;
	wday = 1;
	epoch = 0;
	// The file is one field per line, so it is walked a line at a time rather
	// than split on blanks like a command line.
	lib::each_line(text, &absorb);
	lib::release(text);
	return epoch != 0;
};

fn twodigit(v: u64) void = {
	if (v < 10) {
		rt::putc('0': u8);
	};
	rt::printnum(v);
};

// The chip counts Sunday as one and these are indexed from zero.
fn weekday_name() str = {
	if (wday < 1 || wday > 7) {
		return "???";
	};
	return DAYS[(wday - 1): size];
};

fn month_name() str = {
	if (month < 1 || month > 12) {
		return "???";
	};
	return MONTHS[(month - 1): size];
};

fn iso() void = {
	rt::printnum(year);
	rt::putc('-': u8);
	twodigit(month);
	rt::putc('-': u8);
	twodigit(day);
};

fn clock_time() void = {
	twodigit(hour);
	rt::putc(':': u8);
	twodigit(minute);
	rt::putc(':': u8);
	twodigit(second);
};

fn convert(fmt: []u8) void = {
	for (let i = 0z; i < len(fmt); i += 1) {
		if (fmt[i] != ('%': u8)) {
			rt::putc(fmt[i]);
			continue;
		};
		if (i + 1 >= len(fmt)) {
			// A percent at the very end has nothing to be a code of.
			rt::putc('%': u8);
			return;
		};
		i += 1;
		switch (fmt[i]) {
		case 'Y' =>
			rt::printnum(year);
		case 'y' =>
			twodigit(year % 100);
		case 'm' =>
			twodigit(month);
		case 'd' =>
			twodigit(day);
		case 'H' =>
			twodigit(hour);
		case 'M' =>
			twodigit(minute);
		case 'S' =>
			twodigit(second);
		case 'a' =>
			rt::print(weekday_name());
		case 'b' =>
			rt::print(month_name());
		case 'F' =>
			iso();
		case 'T' =>
			clock_time();
		case 's' =>
			rt::printnum(epoch);
		case '%' =>
			rt::putc('%': u8);
		case => void;
		};
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	if (!read_clock()) {
		rt::println("date: this machine has no clock to read");
		return;
	};
	// The format runs to the end of the line rather than to the first blank.
	// It nearly always has spaces in it, and the shell hands a command over as
	// one run of text with no quoting done to it, so taking the first word
	// would make "date +%a %b %d" print the day of the week and stop.
	let fmt: []u8 = [];
	const start = lib::skip_space(args, 0);
	if (start < len(args) && args[start] == ('+': u8)) {
		fmt = args[start + 1..];
	};
	if (len(fmt) == 0) {
		rt::print(weekday_name());
		rt::putc(' ': u8);
		rt::print(month_name());
		rt::putc(' ': u8);
		rt::printnum(day);
		rt::putc(' ': u8);
		clock_time();
		rt::putc(' ': u8);
		iso();
		rt::println("");
		return;
	};
	convert(fmt);
	rt::println("");
};