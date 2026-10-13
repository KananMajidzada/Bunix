export @symbol("rt.abort") fn _abort(
	path: *str,
	line: u64,
	col: u64,
	msg: str,
) never = {
	print("prog: abort: ");
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
