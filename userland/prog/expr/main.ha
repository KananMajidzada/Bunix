use lib;
use rt;

// Does arithmetic on whole numbers. "expr 2 + 3" is 5, and the operator may
// also be written with letters: add, sub, mul, div, mod.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 3) {
		rt::println("usage: expr <number> <op> <number>");
		return;
	};
	let left: u64 = 0;
	let right: u64 = 0;
	if (lib::number(words[0], &left) == 0 || lib::number(words[2], &right) == 0) {
		rt::println("expr: not a number");
		return;
	};
	const op = words[1];
	let out: u64 = 0;
	if (lib::str_eq(op, *(&"+": *[]u8)) || lib::str_eq(op, *(&"add": *[]u8))) {
		out = left + right;
	} else if (lib::str_eq(op, *(&"-": *[]u8)) || lib::str_eq(op, *(&"sub": *[]u8))) {
		if (right > left) {
			rt::println("expr: the result would be negative");
			return;
		};
		out = left - right;
	} else if (lib::str_eq(op, *(&"*": *[]u8)) || lib::str_eq(op, *(&"mul": *[]u8))) {
		out = left * right;
	} else if (lib::str_eq(op, *(&"/": *[]u8)) || lib::str_eq(op, *(&"div": *[]u8))) {
		if (right == 0) {
			rt::println("expr: cannot divide by zero");
			return;
		};
		out = left / right;
	} else if (lib::str_eq(op, *(&"%": *[]u8)) || lib::str_eq(op, *(&"mod": *[]u8))) {
		if (right == 0) {
			rt::println("expr: cannot divide by zero");
			return;
		};
		out = left % right;
	} else {
		rt::print("expr: unknown operator ");
		rt::println(*(&op: *str));
		return;
	};
	rt::printnum(out);
	rt::println("");
};
