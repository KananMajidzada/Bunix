// Port environment: C compiler driver for Bunix

use rt;
use syscall;

def MAX_ARGS: size = 256;
def MAX_PATH: size = 4096;

export fn main(argc: int, argv: **u8) int = {
	if (argc < 2) {
		rt::println("bcc: no input files");
		return 1;
	};
	
	let input_files: [MAX_ARGS]*u8 = [0...];
	let n_inputs = 0z;
	let output_file: *u8 = (0: *u8);
	let cflags: [MAX_ARGS]*u8 = [0...];
	let n_cflags = 0z;
	let ldflags: [MAX_ARGS]*u8 = [0...];
	let n_ldflags = 0z;
	let compile_only = false;
	let emit_llvm = false;
	
	// Parse arguments
	let i = 1;
	for (i < argc) {
		const arg = argv[i];
		if (arg[0] == ('-': u8)) {
			if (rt::strcmp(arg, "-o") == 0) {
				i += 1;
				if (i < argc) {
					output_file = argv[i];
				};
			} else if (rt::strcmp(arg, "-c") == 0) {
				compile_only = true;
			} else if (rt::strcmp(arg, "-S") == 0) {
				emit_llvm = true;
			} else if (rt::strcmp(arg, "-Wall") == 0 ||
			           rt::strcmp(arg, "-Wextra") == 0 ||
			           rt::strcmp(arg, "-O2") == 0 ||
			           rt::strcmp(arg, "-O3") == 0 ||
			           rt::strcmp(arg, "-g") == 0) {
				cflags[n_cflags] = arg;
				n_cflags += 1;
			} else {
				// Pass through to linker
				ldflags[n_ldflags] = arg;
				n_ldflags += 1;
			};
		} else {
			// Input file
			if (n_inputs < MAX_ARGS) {
				input_files[n_inputs] = arg;
				n_inputs += 1;
			};
		};
		i += 1;
	};
	
	if (n_inputs == 0) {
		rt::println("bcc: no input files");
		return 1;
	};
	
	// Default output
	if (output_file == (0: *u8)) {
		if (compile_only || emit_llvm) {
			// Derive from first input
			const base = rt::basename(input_files[0]);
			if (emit_llvm) {
				output_file = rt::strcat(base, ".ll");
			} else {
				output_file = rt::strcat(base, ".o");
			};
		} else {
			output_file = "a.out";
		};
	};
	
	// Compile each input
	let obj_files: [MAX_ARGS]*u8 = [0...];
	let n_objs = 0z;
	
	for (let j = 0z; j < n_inputs; j += 1) {
		const input = input_files[j];
		let obj: *u8;
		
		if (n_inputs == 1 && !compile_only && !emit_llvm) {
			obj = output_file;
		} else {
			const base = rt::basename(input);
			obj = rt::strcat(base, ".o");
		};
		
		obj_files[n_objs] = obj;
		n_objs += 1;
		
		// For now, just print what we would do
		rt::print("bcc: compiling ");
		rt::print(input);
		rt::print(" -> ");
		rt::println(obj);
		
		// In a real implementation, this would invoke the actual compiler
		// For now, we'll create a placeholder
		if (emit_llvm) {
			// Would emit LLVM IR
			create_placeholder(obj, "LLVM IR");
		} else {
			// Would compile to object
			create_placeholder(obj, "object file");
		};
	};
	
	// Link if not compile-only
	if (!compile_only && !emit_llvm) {
		rt::print("bcc: linking ");
		for (let j = 0z; j < n_objs; j += 1) {
			rt::print(obj_files[j]);
			if (j + 1 < n_objs) {
				rt::print(" ");
			};
		};
		rt::print(" -> ");
		rt::println(output_file);
		
		// Would link here
		create_placeholder(output_file, "executable");
	};
	
	return 0;
};

fn create_placeholder(path: *u8, kind: *u8) void = {
	const fd = syscall::open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644);
	if (fd < 0) {
		rt::println("bcc: cannot create ", path);
		return;
	};
	const content = rt::strcat("# Bunix ", kind, " placeholder\n");
	syscall::write(fd, content, rt::strlen(content));
	syscall::close(fd);
};