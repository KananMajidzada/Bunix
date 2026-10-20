// Helpers the small user programs share: splitting a command line, a few
// string tests, and the line-at-a-time walk every text filter is built on.
// Kept here so each program carries one copy.
//
// Hare has no while loop, so anything that walks to a stopping point goes
// through scan() below rather than each caller growing a second counter to
// keep the position in. A file walks the same way the rest of the tree does.
use rt;

// A slice is a header of pointer, length and capacity, and the helpers below
// need to build one by hand from an address the runtime handed back.
type slice_hdr = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

export fn view(p: uintptr, n: size) []u8 = {
	const h = slice_hdr { data = p, length = n, capacity = n };
	return *(&h: *[]u8);
};

// A slice's own fields are not open to a caller, so the header is read back
// through the struct above. The two layouts are the same, which is the whole
// reason view() can build one.
fn head_of(b: []u8) *slice_hdr = {
	const p = &b: uintptr;
	return p: *slice_hdr;
};

// Where a slice starts and how long it is. The filters that hold many lines at
// once keep them as two flat arrays rather than an array of slices, which
// would cost a header per line for no gain: every one of those lines points
// into one buffer the program is already holding.
export fn at_ptr(b: []u8) uintptr = {
	return head_of(b).data;
};

export fn at_len(b: []u8) size = {
	return head_of(b).length;
};

// ---- character classes ----

export fn is_space(c: u8) bool = {
	return c == (' ': u8) || c == ('\t': u8);
};

export fn is_digit(c: u8) bool = {
	return c >= ('0': u8) && c <= ('9': u8);
};
// Printable and not a control byte, which is what strings and the alignment
// padding both need to recognise.
export fn is_print(c: u8) bool = {
	return c >= (' ': u8) && c < 0x7F;
};

// ---- walking ----

// Walks forward from `from` for as long as `ok` holds on the byte there, and
// says where it stopped. Hare has no while loop, so this is the one place
// that is paid for: every "find where this run ends" below is a call to it,
// rather than each caller growing a second counter to carry the position.
fn scan(b: []u8, from: size, ok: *fn(c: u8) bool) size = {
	let stop = from;
	for (let i = from; i < len(b) && ok(b[i]); i += 1) {
		stop = i + 1;
	};
	return stop;
};

fn is_blank(c: u8) bool = return is_space(c);
fn not_blank(c: u8) bool = return !is_space(c);
fn not_newline(c: u8) bool = return c != ('\n': u8);

// ---- string tests ----

export fn contains(hay: []u8, needle: []u8) bool = {
	if (len(needle) == 0) {
		return true;
	};
	if (len(needle) > len(hay)) {
		return false;
	};
	for (let i = 0z; i + len(needle) <= len(hay); i += 1) {
		let ok = true;
		for (let j = 0z; j < len(needle); j += 1) {
			if (hay[i + j] != needle[j]) {
				ok = false;
				break;
			};
		};
		if (ok) {
			return true;
		};
	};
	return false;
};

export fn str_eq(a: []u8, b: []u8) bool = {
	if (len(a) != len(b)) {
		return false;
	};
	for (let i = 0z; i < len(a); i += 1) {
		if (a[i] != b[i]) {
			return false;
		};
	};
	return true;
};

// The same test against a literal. Nearly every call site has a string in
// hand rather than another buffer, and a str only becomes a []u8 at run time,
// so it cannot be handed to str_eq() directly.
export fn eq_str(a: []u8, b: str) bool = {
	return str_eq(a, *(&b: *[]u8));
};

export fn starts_with(b: []u8, p: []u8) bool = {
	if (len(p) > len(b)) {
		return false;
	};
	return str_eq(b[..len(p)], p);
};

export fn ends_with(b: []u8, p: []u8) bool = {
	if (len(p) > len(b)) {
		return false;
	};
	return str_eq(b[len(b) - len(p)..], p);
};

export fn index_of(b: []u8, c: u8) size = {
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == c) {
			return i;
		};
	};
	return len(b);
};

// ---- trimming ----

// Drops blanks from the end of a line, which is what almost every filter
// wants before it prints one back out.
export fn rtrim(b: []u8) []u8 = {
	let n = len(b);
	for (let i = len(b); i > 0 && (is_space(b[i - 1]) || b[i - 1] == ('\r': u8)); i -= 1) {
		n = i - 1;
	};
	return b[..n];
};

// Drops blanks from the end and then from the front.
export fn trim(b: []u8) []u8 = {
	return rtrim(b[skip_space(b, 0)..]);
};

// ---- numbers ----

// Reads a decimal count. Anything that is not a digit ends the number, and
// `dflt` stands in when the text holds no digits at all, so "-n", "-n3" and
// "-n 3" all end up with something sensible.
export fn parse_int(s: []u8, dflt: u64) u64 = {
	let n = 0u64;
	let seen = false;
	for (let i = 0z; i < len(s) && is_digit(s[i]); i += 1) {
		n = n * 10 + (s[i] - ('0': u8): u64);
		seen = true;
	};
	return if (seen) n else dflt;
};

// ---- command line splitting ----

// The index of the first blank anywhere in the line, or len(b) when there is
// none. This is not skip_space(): that walks over a run of blanks at a
// position, while this is how a command and its arguments are told apart, and
// a line with no arguments at all has to come back as the whole of the line.
export fn first_space(b: []u8) size = {
	for (let i = 0z; i < len(b); i += 1) {
		if (is_space(b[i])) {
			return i;
		};
	};
	return len(b);
};

export fn skip_space(b: []u8, from: size) size = {
	return scan(b, from, &is_blank);
};

// Where the token starting at `pos` ends.
export fn token_end(b: []u8, pos: size) size = {
	return scan(b, pos, &not_blank);
};

// The next argument at or after `from`, and where the one after it begins.
// The returned slice points into `b`.
export fn next_arg(b: []u8, from: size) ([]u8, size) = {
	const start = skip_space(b, from);
	const end = token_end(b, start);
	return (b[start..end], skip_space(b, end));
};

// The nth argument, counting from the first one after the program name.
// A count past the end gives an empty slice.
export fn arg_n(b: []u8, n: size) []u8 = {
	let pos = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (pos >= len(b)) {
			return b[len(b)..];
		};
		let (tok, next) = next_arg(b, pos);
		pos = next;
		if (i == n) {
			return tok;
		};
	};
	return b[len(b)..];
};

// How many arguments follow the program name.
export fn count_args(b: []u8) size = {
	let n = 0z;
	let pos = skip_space(b, 0);
	for (let i = 0z; pos < len(b); i += 1) {
		n = i + 1;
		pos = next_arg(b, pos).1;
	};
	return n;
};

// The value of a flag, in either of the two forms a shell accepts: "-n 5"
// takes the next argument, "-n5" takes the rest of this one. `width` is how
// long the flag itself is, so "-n 5" and "-c," can share this. When nothing
// follows the flag the default stands and the line is left where it was, so a
// filter with a flag and no file still reads the one path it was given.
export fn flag_val(b: []u8, pos: size, width: size, dflt: u64) (u64, size) = {
	const tok = b[pos..token_end(b, pos)];
	if (len(tok) > width) {
		const v = parse_int(tok[width..], dflt);
		return (v, skip_space(b, pos + len(tok)));
	};
	const after = skip_space(b, pos + width);
	if (after >= len(b)) {
		return (dflt, pos);
	};
	let (val, next) = next_arg(b, after);
	return (parse_int(val, dflt), next);
};

// ---- files ----

// The whole file in one piece of memory, or an empty slice when it cannot be
// read. The caller hands the result back with release(). A generated file such
// as /proc/uptime reports no length from a stat, so the buffer has a floor
// rather than a size taken from one.
export fn slurp(path: []u8) []u8 = {
	const p = *(&path: *str);
	if (!rt::exists(p)) {
		return [];
	};
	let want = rt::filesize(p);
	if (want < 4096) {
		want = 4096;
	} else {
		want += 1;
	};
	const mem = rt::malloc(want);
	const addr = match (mem) {
	case null =>
		return [];
	case let q: *opaque =>
		yield q: uintptr;
	};
	const buf = view(addr, want);
	return buf[..rt::readfile(p, buf)];
};

// Hands back what slurp took. The slice still points at the first byte, which
// is exactly the address the runtime handed out. Only for a buffer that came
// from slurp: freeing a static array would take memory the runtime never had.
export fn release(b: []u8) void = {
	rt::free_(head_of(b).data: *opaque);
};

// Reads a directory into one buffer of newline separated names, which is the
// shape the kernel hands back. Empty for a file, or for a path that is not
// there.
export fn listdir(path: []u8) []u8 = {
	const p = *(&path: *str);
	return dirbuf[..rt::readdir(p, dirbuf[..])];
};

def DIRCAP: size = 4096;
let dirbuf: [DIRCAP]u8 = [0...];

// The name that starts at `pos` in a directory listing, and where the next one
// begins.
export fn name_at(list: []u8, pos: size) ([]u8, size) = {
	const end = scan(list, pos, &not_newline);
	return (list[pos..end], if (end < len(list)) end + 1 else len(list));
};

// Walks the lines of a buffer, giving `visit` each one without its newline.
// A last line that ends without a newline still counts, but the empty string
// after a trailing newline does not. Returning false stops the walk, which is
// how head stops early instead of reading on past what it was asked for.
export fn each_line(text: []u8, visit: *fn(line: []u8) bool) void = {
	let start = 0z;
	for (let i = 0z; i < len(text); i += 1) {
		if (text[i] == ('\n': u8)) {
			if (!visit(text[start..i])) {
				return;
			};
			start = i + 1;
		};
	};
	// Whatever is left has no newline of its own. When the buffer ended with
	// one this is empty, and an empty tail is not a line of its own.
	if (start < len(text)) {
		visit(text[start..]);
	};
};

let counted: u64 = 0;

fn count_one(line: []u8) bool = {
	counted += 1;
	return true;
};

// ---- output ----

// The header a multi-file filter puts above each file, the way head, tail and
// cat do, so it is obvious which part of the output came from where.
export fn banner(path: []u8) void = {
	rt::print("==> ");
	rt::write(path);
	rt::println(" <==");
};

// The last element of a path, which is what "mv a/b c" puts in the new
// directory and what a listing shows as the name.
export fn base_name(path: []u8) []u8 = {
	const slash = last_slash(path);
	return path[slash..];
};

fn last_slash(path: []u8) size = {
	let at = 0z;
	for (let i = 0z; i < len(path); i += 1) {
		if (path[i] == ('/': u8)) {
			at = i + 1;
		};
	};
	return at;
};

// The root itself. A str only becomes a slice at run time, so this cannot be
// a value the file holds; it has to be asked for.
export fn root_dir() []u8 = {
	return *(&"/": *[]u8);
};
