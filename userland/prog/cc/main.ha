// Compiler driver for Bunix (placeholder).
// The real bcc runs on the host and cross-compiles for Bunix.
// This in-kernel version just prints a message.

use rt;

export @symbol("main") fn main() void = {
	const a = rt::arg();
	const line = *(&a: *[]u8);

	if (len(line) == 0) {
		rt::println("bcc: Bunix C compiler driver (placeholder)");
		rt::println("usage: bcc [-o outfile] file.c ...");
		rt::println("note: real bcc runs on host, not inside Bunix");
		return;
	};

	rt::print("bcc: would compile ");
	rt::write(line);
	rt::println("");
	rt::println("bcc: this is a placeholder; run the host-side bcc instead");
};