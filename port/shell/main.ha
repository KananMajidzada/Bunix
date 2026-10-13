// Port environment: POSIX-compatible shell

use bfp;
use rt;
use syscall;

def MAX_LINE: size = 4096;
def MAX_ARGS: size = 64;
def MAX_PATH: size = 1024;

let history: [100]str = [0...];
let hist_count = 0z;

export fn main() void = {
	const cwd: [MAX_PATH]u8 = [0...];
	
	for (true) {
		// Get current working directory
		syscall.getcwd(&cwd, MAX_PATH);
		
		// Print prompt
		const user = syscall.getlogin();
		rt::print(user);
		rt::print("@bunix:");
		rt::print(cwd);
		rt::print("$ ");
		
		// Read line
		let line: [MAX_LINE]u8 = [0...];
		const len = read_line(&line, MAX_LINE);
		if (len == 0) {
			rt::print("\n");
			continue;
		};
		
		// Add to history
		if (hist_count < 100) {
			history[hist_count] = rt::slice_to_str(line[..len]);
			hist_count += 1;
		};
		
		// Parse and execute
		execute_line(&line, len);
	};
};

fn read_line(buf: *u8, max: size) size = {
	let i = 0z;
	for (i < max - 1) {
		const ch = syscall::read(STDIN_FILENO, buf + i, 1);
		if (ch <= 0) {
			break;
		};
		if (buf[i] == ('\n': u8)) {
			buf[i] = 0;
			break;
		};
		if (buf[i] == ('\r': u8)) {
			buf[i] = 0;
			break;
		};
		i += 1;
	};
	return i;
};

fn execute_line(buf: *u8, len: size) void = {
	let argc = 0z;
	let argv: [MAX_ARGS]*u8 = [0...];
	
	// Parse arguments
	let i = 0z;
	for (i < len && argc < MAX_ARGS) {
		// Skip whitespace
		for (i < len && (buf[i] == (' ': u8) || buf[i] == ('\t': u8))) {
			i += 1;
		};
		if (i >= len) {
			break;
		};
		
		argv[argc] = buf + i;
		argc += 1;
		
		// Find end of argument
		for (i < len && buf[i] != (' ': u8) && buf[i] != ('\t': u8)) {
			i += 1;
		};
		if (i < len) {
			buf[i] = 0;
			i += 1;
		};
	};
	argv[argc] = (0: *u8);
	
	if (argc == 0) {
		return;
	};
	
	// Built-in commands
	if (rt::strcmp(argv[0], "exit") == 0) {
		syscall::exit(0);
	} else if (rt::strcmp(argv[0], "cd") == 0) {
		if (argc < 2) {
			const home = syscall::getenv("HOME");
			if (home != (0: *u8)) {
				syscall::chdir(home);
			};
		} else {
			syscall::chdir(argv[1]);
		};
	} else if (rt::strcmp(argv[0], "pwd") == 0) {
		const cwd: [MAX_PATH]u8 = [0...];
		syscall::getcwd(&cwd, MAX_PATH);
		rt::println(cwd);
	} else if (rt::strcmp(argv[0], "echo") == 0) {
		for (let j = 1z; j < argc; j += 1) {
			rt::print(argv[j]);
			if (j + 1 < argc) {
				rt::print(" ");
			};
		};
		rt::print("\n");
	} else if (rt::strcmp(argv[0], "help") == 0) {
		rt::println("Built-in commands:");
		rt::println("  exit           - Exit the shell");
		rt::println("  cd [dir]       - Change directory");
		rt::println("  pwd            - Print working directory");
		rt::println("  echo [args]    - Print arguments");
		rt::println("  help           - Show this help");
		rt::println("  clear          - Clear screen");
		rt::println("  history        - Show command history");
	} else if (rt::strcmp(argv[0], "clear") == 0) {
		syscall::write(STDOUT_FILENO, "\x1b[2J\x1b[H", 7);
	} else if (rt::strcmp(argv[0], "history") == 0) {
		for (let j = 0z; j < hist_count; j += 1) {
			rt::printnum(j + 1);
			rt::print("  ");
			rt::println(history[j]);
		};
	} else {
		// External command - fork and exec
		const pid = syscall::fork();
		if (pid == 0) {
			// Child
			syscall::exec(argv[0], argv, (0: *const *const u8));
			rt::println("command not found: ", argv[0]);
			syscall::exit(127);
		} else if (pid > 0) {
			// Parent
			let status = 0;
			syscall::waitpid(pid, &status, 0);
		} else {
			rt::println("fork failed");
		};
	};
};