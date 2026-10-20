use lib;
use rt;

// head [-n lines] [file...]
//
// The first lines of a file, ten unless the command says otherwise. With more
// than one file each gets a banner, the way cat does, so it stays clear which
// part of the output came from where.

let limit: u64 = 10;
let seen: u64 = 0;

fn take(line: []u8) bool = {
	if (seen >= limit) {
		return false;
	};
	seen += 1;
	rt::write(line);
	rt::println("");
	return true;
};

fn head_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("head: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	seen = 0;
	lib::each_line(text, &take);
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	// -n 5, -n5 and a bare -5 all name the count. A flag with nothing after it
	// keeps the default and leaves the line alone, so the path behind it still
	// reads as a path.
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) > 1 && tok[1] == ('n': u8)) {
			let (v, next) = lib::flag_val(args, pos, 2, limit);
			limit = v;
			pos = next;
			continue;
		};
		if (len(tok) > 1 && lib::is_digit(tok[1])) {
			limit = lib::parse_int(tok[1..], limit);
			pos = lib::skip_space(args, pos + len(tok));
			continue;
		};
		rt::print("head: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (nfiles > 0) {
			lib::banner(path);
		};
		head_file(path);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: head [-n lines] [file...]");
	};
};