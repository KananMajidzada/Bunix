// A write hook the kernel installs during startup so that runtime failures can
// be reported. While it is null, aborts stop the machine silently.
export let con_write: nullable *fn(buf: []u8) size = null;

fn print(s: str) void = {
	const buf = *(&s: *[]u8);
	match (con_write) {
	case null => void;
	case let f: *fn(buf: []u8) size =>
		f(buf);
	};
};

fn printnum(n: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	if (n == 0) {
		i -= 1;
		buf[i] = '0': u8;
	} else {
		for (n > 0) {
			i -= 1;
			buf[i] = ((n % 10): u8) + ('0': u8);
			n /= 10;
		};
	};
	match (con_write) {
	case null => void;
	case let f: *fn(buf: []u8) size =>
		f(buf[i..]);
	};
};

export @symbol("rt.abort") fn _abort(
	path: *str,
	line: u64,
	col: u64,
	msg: str,
) never = {
	print("bunix: abort: ");
	print(*path);
	print(":");
	printnum(line);
	print(":");
	printnum(col);
	print(": ");
	print(msg);
	print("\n");
	halt();
};

// Indexed by the compiler's fixed list of runtime conditions.
const reasons: [_]str = [
	"slice or array access out of bounds",
	"type assertion failed",
	"out of memory",
	"static insert/append exceeds slice capacity",
	"execution reached unreachable code",
	"slice allocation capacity smaller than initializer",
	"assertion failed",
	"error occurred",
];

export fn abort_fixed(path: *str, line: u64, col: u64, i: u64) void = {
	_abort(path, line, col, reasons[i: size]);
};
