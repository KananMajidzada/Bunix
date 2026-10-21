use lib;
use rt;

// Stops a process. The number of the process is given, and the process is
// not told about it first.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: kill <pid>");
		return;
	};
	let id: u64 = 0;
	if (lib::number(words[0], &id) == 0) {
		rt::println("kill: not a process number");
		return;
	};
	if (rt::kill(id)) {
		rt::print("killed ");
		rt::printnum(id);
		rt::println("");
	} else {
		rt::print("kill: no such process: ");
		rt::printnum(id);
		rt::println("");
	};
};
