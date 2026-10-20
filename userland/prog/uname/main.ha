use lib;
use rt;

// uname [-a]
//
// The system's name and version, which is what /proc/version is built out of.
// Plain uname names the system; -a gives the whole thing, banner and all,
// which is what a person running "uname -a" on another machine expects to see.

fn vpath() []u8 = {
	return *(&"/proc/version": *[]u8);
};

fn osmark() []u8 = {
	return *(&"OS: ": *[]u8);
};

let empty: []u8 = [];

// The name that follows "OS: ". The version lines carry the banner art in
// front of the text, so the name is looked for inside a line rather than
// assumed to be at the front of one.
fn osname(v: []u8) []u8 = {
	const mark = osmark();
	let at = 0z;
	for (let i = 0z; i < len(v); i += 1) {
		if (v[i] == mark[0]) {
			at = i;
			break;
		};
	};
	if (at >= len(v)) {
		return empty;
	};
	const tail = v[at..];
	if (!lib::starts_with(tail, mark)) {
		return empty;
	};
	// The name runs to the end of that line and no further.
	let end = len(mark);
	for (let i = len(mark); i < len(tail) && tail[i] != ('\n': u8); i += 1) {
		end = i + 1;
	};
	return lib::trim(tail[len(mark)..end]);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	const v = lib::slurp(vpath());
	if (len(v) == 0) {
		rt::println("uname: no version file");
		return;
	};
	if (lib::eq_str(lib::arg_n(args, 0), "-a")) {
		rt::write(v);
	} else {
		const name = osname(v);
		if (len(name) == 0) {
			rt::println("unknown");
		} else {
			rt::println(*(&name: *str));
		};
	};
	lib::release(v);
};