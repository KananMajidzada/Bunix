use lib;
use rt;

// tr [-d] [-s] set1 [set2]
//
// Replaces, deletes or squeezes characters. Each byte of set1 becomes the byte
// at the same place in set2, so a shorter set2 pads out with its last byte.
//
// A run in a set, as in "a-z", stands for every byte between its ends, which is
// what makes "tr a-z A-Z" do what it looks like it does. Without that the
// commonest call of all would translate the letter before the dash, the dash,
// and the letter after it, and nothing else.
//
// -d removes set1 instead, and -s folds a run of the same byte down to one.

let dropping: bool = false;
let squeeze: bool = false;

// Which bytes set1 named, for -d.
let inset: [256]bool = [false...];
// Where each byte goes, for the ordinary case.
let trans: [256]u8 = [0...];

// One line of input at a time. The keyboard is the only source here, so there
// is no pipe to read in anything bigger than this.
let line: [512]u8 = [0...];

// What a backslash stands for. A person typing at a shell means a newline
// when they write \n, not a backslash followed by an n.
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
	return e;
};

// Reads one set into out, expanding escapes and runs, and says how long it is.
fn reads(src: []u8, out: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(src); i += 1) {
		let c = src[i];
		if (c == ('\\': u8) && i + 1 < len(src)) {
			c = escape(src[i + 1]);
			i += 1;
		} else if (i + 2 < len(src) && src[i + 1] == '-') {
			// A run, as in a-z. The high end may itself be escaped.
			let hi = src[i + 2];
			let step: size = 1;
			if (hi == ('\\': u8) && i + 3 < len(src)) {
				hi = escape(src[i + 3]);
				step = 2;
			};
			// A run that runs backwards would never end if it were walked
			// with a signed step, so it is taken as the two ends on their own.
			if (hi >= c) {
				for (let k = c; k <= hi && n < len(out); k += 1) {
					out[n] = k;
					n += 1;
				};
			};
			i += 2 + step - 1;
			continue;
		};
		if (n < len(out)) {
			out[n] = c;
			n += 1;
		};
	};
	return n;
};

// Turns the two sets into the tables the translate below reads, so the work of
// deciding what each byte becomes is done once rather than once per byte of
// the input.
fn build(from: []u8, nfrom: size, to: []u8, nto: size) void = {
	for (let i = 0z; i < len(trans); i += 1) {
		trans[i] = i: u8;
		inset[i] = false;
	};
	for (let i = 0z; i < nfrom; i += 1) {
		const c = from[i];
		inset[c] = true;
		let t = c;
		if (nto > 0) {
			t = if (i < nto) to[i] else to[nto - 1];
		};
		trans[c] = t;
	};
};

fn translate(text: []u8) void = {
	let last: u8 = 0;
	for (let i = 0z; i < len(text); i += 1) {
		const c = text[i];
		if (dropping && inset[c]) {
			continue;
		};
		const out = if (dropping) c else trans[c];
		if (squeeze && i > 0 && out == last) {
			continue;
		};
		rt::putc(out);
		last = out;
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('d': u8)) {
			dropping = true;
		} else if (len(tok) == 2 && tok[1] == ('s': u8)) {
			squeeze = true;
		} else {
			rt::print("tr: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		pos = lib::skip_space(args, pos + len(tok));
	};

	let from: [256]u8 = [0...];
	let to: [256]u8 = [0...];
	const f1 = lib::arg_n(args, 0);
	if (len(f1) == 0) {
		rt::println("usage: tr [-d] [-s] set1 [set2]");
		return;
	};
	const nfrom = reads(f1, from[..]);
	let nto = 0z;
	if (!dropping) {
		const f2 = lib::arg_n(args, 1);
		if (len(f2) == 0) {
			rt::println("tr: set2 is needed unless -d is given");
			return;
		};
		nto = reads(f2, to[..]);
	};
	build(from[..nfrom], nfrom, to[..nto], nto);

	// Input is taken a line at a time until the keyboard is closed with
	// Ctrl-D, so tr works here the way it does on a pipe.
	for (true) {
		let n = 0z;
		for (true) {
			const c = rt::getchar();
			if (c == 4) {
				if (n > 0) {
					translate(line[..n]);
				};
				return;
			};
			if (c == ('\n': u8)) {
				break;
			};
			if (n < len(line)) {
				line[n] = c;
				n += 1;
			};
		};
		translate(line[..n]);
		rt::println("");
	};
};