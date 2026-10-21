use lib;
use rt;

// The machine this is running on.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n > 0 && lib::str_eq(words[0], *(&"-a": *[]u8))) {
		// Everything there is to say.
		rt::println("Bunix 0.1 x86_64 bunix");
		return;
	};
	rt::println("Bunix");
};
