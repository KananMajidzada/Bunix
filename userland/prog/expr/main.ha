use lib;
use rt;

// expr operand...
//
// Whole-number arithmetic: addition, subtraction, multiplication, division and
// remainder, with parentheses and a leading minus. It exists so a number can
// be worked out at the prompt without a person doing it, which is what a shell
// script wants and what this shell, having no variables and no pipes, cannot
// otherwise arrange.
//
// The grammar is the usual one and is parsed by the same descent the C
// compiler uses for expressions: multiplication binds tighter than addition,
// and a parenthesis takes precedence over both.

let text: []u8 = [];
let pos: size = 0;
let bad: bool = false;

def NOFOUND: size = ~0z;

// Over the blanks before wherever we have got to. The test is on text at pos
// and not at the loop counter: the counter is only what gives the loop
// something to count, and reading the wrong index here makes every operator
// after the first number look like it is trailing rubbish.
fn skip() void = {
	for (let k = 0z; pos < len(text) && lib::is_space(text[pos]); k += 1) {
		pos += 1;
	};
};

fn at(c: u8) bool = {
	skip();
	return pos < len(text) && text[pos] == c;
};

fn eat(c: u8) bool = {
	if (at(c)) {
		pos += 1;
		return true;
	};
	return false;
};

// A whole number, or nothing. A word that is not one is left where it is so
// the caller can see what went wrong rather than being read as a zero.
fn number() i64 = {
	skip();
	const start = pos;
	let n: i64 = 0;
	for (let i = 0z; pos < len(text) && lib::is_digit(text[pos]); i += 1) {
		n = n * 10 + ((text[pos] - ('0': u8)): i64);
		pos += 1;
	};
	if (pos == start) {
		bad = true;
		return 0;
	};
	return n;
};

// expression := product (('+' | '-') product)*
fn expression() i64 = {
	let v = product();
	for (true) {
		skip();
		if (eat('+': u8)) {
			v += product();
			continue;
		};
		if (eat('-': u8)) {
			v -= product();
			continue;
		};
		return v;
	};
};

// product := value (('*' | '/' | '%') value)*
fn product() i64 = {
	let v = value();
	for (true) {
		skip();
		if (eat('*': u8)) {
			v *= value();
			continue;
		};
		if (eat('/': u8)) {
			const d = value();
			// Dividing by nothing is an error a shell script should notice
			// rather than have come back as a machine's idea of the answer.
			if (d == 0) {
				bad = true;
				return 0;
			};
			v /= d;
			continue;
		};
		if (eat('%': u8)) {
			const d = value();
			if (d == 0) {
				bad = true;
				return 0;
			};
			v %= d;
			continue;
		};
		return v;
	};
};

// value := number | '-' value | '(' expression ')'
fn value() i64 = {
	skip();
	if (eat('-': u8)) {
		return -value();
	};
	if (eat('(': u8)) {
		const v = expression();
		if (!eat(')': u8)) {
			bad = true;
			return 0;
		};
		return v;
	};
	return number();
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	// The whole line is the expression, not one argument at a time: a space
	// between two numbers is what multiplication looks like to a person.
	text = lib::trim(args);
	if (len(text) == 0) {
		rt::println("usage: expr operand...");
		return;
	};
	pos = 0;
	bad = false;
	const v = expression();
	skip();
	if (pos < len(text)) {
		rt::print("expr: cannot read ");
		rt::println(*(&text[pos..]: *str));
		return;
	};
	if (bad) {
		rt::println("expr: not a whole-number expression");
		return;
	};
	// Negative numbers print with a sign of their own; printnum deals in
	// unsigned and would wrap one round to something enormous.
	if (v < 0) {
		rt::putc('-': u8);
	};
	let n = if (v < 0) -v else v;
	let buf: [20]u8 = [0...];
	let i = len(buf);
	if (n == 0) {
		i -= 1;
		buf[i] = ('0': u8);
	} else {
		for (let k = 0u64; n > 0; k += 1) {
			i -= 1;
			buf[i] = ((n % 10): u8) + ('0': u8);
			n /= 10;
		};
	};
	rt::write(buf[i..]);
	rt::println("");
};