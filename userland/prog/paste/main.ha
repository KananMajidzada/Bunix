use lib;
use rt;

// paste [-d sep] file...
//
// Corresponding lines of several files put side by side. The first line of
// each goes on one line of output, the second lines together, and so on; a
// file that runs out first leaves the rest of its column empty rather than
// ending the row, which is what makes the two halves line up.
//
// A tab is what goes between them unless -d says otherwise. Most of the
// reason to want this at all is to hand something to awk or column, and both
// of those would rather have a tab.

// Four files is as many as there is room for in the buffers below, and is
// more than anyone has ever wanted to compare sideways.
def MAXFILES: size = 8;

let texts: [MAXFILES][]u8 = [[]...];
let nfiles: size = 0;

fn line_at(text: []u8, want: size) []u8 = {
	let at = 0z;
	let found = 0z;
	let start = 0z;
	for (let i = 0z; i <= len(text); i += 1) {
		if (i == len(text) || text[i] == ('\n': u8)) {
			if (found == want) {
				let stop = i;
				// The newline is not part of the line it ends.
				if (stop > start && text[stop - 1] == ('\r': u8)) {
					stop -= 1;
				};
				return text[start..stop];
			};
			found += 1;
			start = i + 1;
		};
	};
	return empty;
};

let empty: []u8 = [];

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let sep: []u8 = *(&"\t": *[]u8);

	if (pos < len(args) && args[pos] == ('-': u8)) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) == 2 && tok[1] == ('d': u8)) {
			pos = lib::skip_space(args, pos + len(tok));
			let (given, next) = lib::next_arg(args, pos);
			if (len(given) > 0) {
				sep = given;
				pos = next;
			};
		};
	};

	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		pos = next;
		if (nfiles >= MAXFILES) {
			rt::print("paste: only the first ");
			rt::printnum(MAXFILES: u64);
			rt::println(" files are used");
			break;
		};
		const text = lib::slurp(path);
		if (len(text) == 0) {
			rt::print("paste: cannot read ");
			rt::println(*(&path: *str));
			continue;
		};
		texts[nfiles] = text;
		nfiles += 1;
	};
	if (nfiles == 0) {
		rt::println("usage: paste [-d sep] <file>...");
		return;
	};

	// How many lines the longest file has, which is how many rows there are.
	let rows = 0z;
	for (let i = 0z; i < nfiles; i += 1) {
		let n = 0z;
		for (let k = 0z; k < len(texts[i]); k += 1) {
			if (texts[i][k] == ('\n': u8)) {
				n += 1;
			};
		};
		// A file whose last line has no newline on the end still has a line
		// in it, which is a thing a lot of programs get wrong.
		if (len(texts[i]) > 0 && texts[i][len(texts[i]) - 1] != ('\n': u8)) {
			n += 1;
		};
		if (n > rows) {
			rows = n;
		};
	};

	for (let r = 0z; r < rows; r += 1) {
		let printed = 0z;
		for (let i = 0z; i < nfiles; i += 1) {
			const line = line_at(texts[i], r);
			if (printed > 0) {
				rt::write(sep);
			};
			rt::write(line);
			printed += 1;
		};
		rt::println("");
	};

	for (let i = 0z; i < nfiles; i += 1) {
		lib::release(texts[i]);
	};
};