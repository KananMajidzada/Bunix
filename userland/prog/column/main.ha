use lib;
use rt;

// column [file]
//
// Lines put into columns, which is what turns a list too long to read down
// the screen into something that fits on it.
//
// Columns are as wide as the longest thing in them and are separated by two
// blanks, so what it fits depends on the longest entry rather than on the
// number of them. There are no pipes, so the list to arrange has to be a file:
//
//	ls /bin > /tmp/names
//	column /tmp/names

def WIDTH: size = 78;

def MAXROWS: size = 1024;

let names: [MAXROWS][]u8 = [[]...];
let nrows: size = 0;
let dropped: size = 0;

fn take(line: []u8) bool = {
	const t = lib::trim(line);
	if (len(t) == 0) {
		return true;
	};
	if (nrows >= MAXROWS) {
		dropped += 1;
		return true;
	};
	names[nrows] = t;
	nrows += 1;
	return true;
};

fn widest() size = {
	let w = 0z;
	for (let i = 0z; i < nrows; i += 1) {
		if (len(names[i]) > w) {
			w = len(names[i]);
		};
	};
	return w;
};

fn layout() size = {
	// How many columns fit, given how wide the widest entry is. An entry as
	// wide as the screen gets a column of its own, which is the degenerate
	// case but the only one that cannot be wrong.
	const w = widest() + 2;
	if (w > WIDTH) {
		return 1;
	};
	return WIDTH / w;
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	const path = lib::arg_n(args, 0);
	let text: []u8 = [];
	if (len(path) > 0) {
		text = lib::slurp(path);
		if (len(text) == 0) {
			rt::print("column: cannot read ");
			rt::println(*(&path: *str));
			return;
		};
	};
	lib::each_line(text, &take);
	if (len(text) > 0) {
		lib::release(text);
	};
	if (nrows == 0) {
		return;
	};

	const cell = widest();
	const cols = layout();
	// Read down each column rather than along each row, which is the order a
	// name list makes sense in: the ones at the top are the ones that were
	// there first.
	const rows = (nrows + cols - 1) / cols;

	for (let r = 0z; r < rows; r += 1) {
		for (let c = 0z; c < cols; c += 1) {
			const at = c * rows + r;
			if (at >= nrows) {
				continue;
			};
			const entry = names[at];
			rt::write(entry);
			// Pad out to the column width, but not after the last entry on
			// the line: trailing blanks are not worth a line of their own.
			const last = (c + 1) * rows + r >= nrows;
			if (!last) {
				for (let k = len(entry); k < cell + 2; k += 1) {
					rt::putc(' ': u8);
				};
			};
		};
		rt::println("");
	};
	if (dropped > 0) {
		rt::print("column: ");
		rt::printnum(dropped: u64);
		rt::println(" entries did not fit");
	};
};