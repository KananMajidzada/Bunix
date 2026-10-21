use lib;
use rt;

// The processes that are running. The number of each one comes first, and
// then the command it was started with.
export @symbol("main") fn main() void = {
	const list = rt::ps();
	let start = 0z;
	for (let i = 0z; i <= len(list); i += 1) {
		if (i == len(list) || list[i] == ('\n': u8)) {
			if (i > start) {
				const line = list[start..i];
				// The number is padded out so the commands line up.
				let pad = 0z;
				for (let j = 0z; j < len(line) && line[j] != (' ': u8); j += 1) {
					pad += 1;
				};
				for (let k = pad; k < 5; k += 1) {
					rt::putc(' ');
				};
				rt::write(line);
				rt::println("");
			};
			start = i + 1;
		};
	};
};
