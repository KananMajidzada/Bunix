use lib;
use rt;

// printf "<format>" [argument]...
//
// Prints a format with the arguments after it filled in. This is the other
// half of echo: echo has no way to say where the text should go or what number
// it is, and printf has no way to say anything at all except a format.
//
// A conversion is a percent sign, an optional field of zeros, and one letter.
// %s takes a string, %d a whole number, %x the same in hex, %c a single
// character, %% a percent sign of its own. A backslash in the format means the
// byte it stands for, so a newline is written \\n. Anything the printer does
// not recognise is copied out as it stands, which is better than swallowing it
// and the argument with it.
//
// The shell hands a command over as one run of text and does no quoting of its
// own, so the format is read as the run inside a pair of quotes when it is
// written between them and as the first word when it is not.

def MAXLINE: size = 512;
let out: []u8 = [];

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

fn putnum(v: u64, base: u64, places: size) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	let x = v;
	if (x == 0) {
		i -= 1;
		buf[i] = ('0': u8);
	} else {
		for (let k = 0u64; x > 0; k += 1) {
			i -= 1;
			buf[i] = hexdig((x % base): u8);
			x /= base;
		};
	};
	// Zeros in the field pad on the left to the width asked for, which is how
	// a column of numbers is made to line up.
	for (let k = i; k < places; k += 1) {
		rt::putc('0': u8);
	};
	rt::write(buf[i..]);
};

// The argument being read, whole.
fn want() []u8 = {
	const v = lib::arg_n(out, curarg);
	if (len(v) > 0) {
		curarg += 1;
	};
	curoff = 0;
	return v;
};

// The next byte of the argument being read. Running out prints nothing rather
// than the same byte twice.
fn wantchar() u8 = {
	const v = lib::arg_n(out, curarg);
	if (curoff >= len(v)) {
		return 0;
	};
	const c = v[curoff];
	curoff += 1;
	return c;
};

// Which argument is being read, and how far into it. They are separate because
// a run of %c takes its bytes one at a time out of the same argument, which is
// what makes "%c%c" print two letters of one word rather than two words.
let curarg: size = 0;
let curoff: size = 0;

// What a backslash stands for. A person writing a newline means a newline,
// not a backslash and an n.
fn escape(e: u8) u8 = {
	if (e == ('n': u8)) {
		return ('\n': u8);
	};
	if (e == ('t': u8)) {
		return ('\t': u8);
	};
	if (e == ('r': u8)) {
		return ('\r': u8);
	};
	if (e == ('0': u8)) {
		return 0;
	};
	if (e == ('\\': u8)) {
		return ('\\': u8);
	};
	return e;
};

// One conversion, starting at the zeros of its field width. Returns how many
// bytes of the format it used, so the caller can step over them.
fn convert(fmt: []u8, from: size) size = {
	// The digits before the letter are a field width. How many of them there
	// are and how wide the field is are two different numbers: "%04x" has two
	// digits and a field four wide, and the letter is after the second of
	// them, not after four bytes.
	let digits = 0z;
	let places = 0z;
	for (let i = from; i < len(fmt) && lib::is_digit(fmt[i]); i += 1) {
		digits += 1;
		places = places * 10 + (fmt[i] - ('0': u8): size);
	};
	if (from + digits >= len(fmt)) {
		// A percent with nothing to convert it into.
		rt::print("%");
		rt::write(fmt[from..]);
		return len(fmt) - from;
	};
	const letter = fmt[from + digits];

	if (letter == ('%': u8)) {
		rt::putc('%': u8);
	} else if (letter == ('s': u8)) {
		rt::write(want());
	} else if (letter == ('c': u8)) {
		rt::putc(wantchar());
	} else if (letter == ('d': u8) || letter == ('u': u8)) {
		putnum(lib::parse_int(want(), 0), 10, places);
	} else if (letter == ('x': u8)) {
		putnum(lib::parse_int(want(), 0), 16, places);
	} else {
		// Not a conversion this printf knows. It is copied out as written,
		// and the argument it would have taken is left for the next one.
		rt::print("%");
		rt::write(fmt[from..from + digits + 1]);
	};
	return digits + 1;
};

// Where the format ends and the arguments begin.
fn formatsplit(args: []u8) ([]u8, size) = {
	const first = lib::skip_space(args, 0);
	if (first < len(args)) {
		const q = args[first];
		if (q == ('"': u8) || q == 39) {
			let i = first + 1;
			for (let k = 0z; i < len(args) && args[i] != q; k += 1) {
				i += 1;
			};
			if (i < len(args)) {
				return (args[first + 1..i], lib::skip_space(args, i + 1));
			};
		};
	};
	const end = lib::token_end(args, first);
	return (args[first..end], lib::skip_space(args, end));
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let (fmt, pos) = formatsplit(args);
	if (len(fmt) == 0) {
		rt::println("usage: printf \"<format>\" [argument]...");
		return;
	};
	// The arguments are everything after the format, kept as one run of text
	// so that a conversion can be told apart from an argument that happens to
	// look like one.
	out = args[pos..];
	curarg = 0;
	curoff = 0;

	let i = 0z;
	for (let k = 0z; i < len(fmt); k += 1) {
		const c = fmt[i];
		if (c == ('\\': u8) && i + 1 < len(fmt)) {
			rt::putc(escape(fmt[i + 1]));
			// Past the backslash and the byte it stands for, or the byte
			// after the pair would be printed a second time.
			i += 2;
			continue;
		};
		if (c != ('%': u8)) {
			rt::putc(c);
			i += 1;
			continue;
		};
		if (i + 1 >= len(fmt)) {
			// A percent at the very end has nothing to be a conversion of.
			rt::putc('%': u8);
			i += 1;
			continue;
		};
		// convert() wants the first byte of the conversion, which is the one
		// after the percent, and says how many of them it used.
		const spec = convert(fmt, i + 1);
		i += spec + 1;
	};
	rt::println("");
};