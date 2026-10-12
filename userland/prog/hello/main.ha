use rt;

// The smallest program with an image of its own; it proves the loader can run
// a second executable next to the shell.
export @symbol("main") fn main() void = {
	rt::println("hello from its own program");
};
