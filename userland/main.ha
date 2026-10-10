use rt;

export @symbol("main") fn main() void = {
	rt::println("hello from a Hare user program");

	let buf: [128]u8 = [0...];
	const n = rt::readfile("/proc/version", buf[..]);
	rt::print("version: ");
	rt::write(buf[..n]);

	const s: str = "heap works";
	const msg = *(&s: *[]u8);
	let built: []u8 = [];
	for (let i = 0z; i < len(msg); i += 1) {
		append(built, msg[i])!;
	};
	rt::print("heap: ");
	rt::write(built);
	rt::println("");
	free(built);
};
