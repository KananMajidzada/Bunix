use lib;
use rt;

def MAXEXTPROG: size = 64;
def ARENASZ: size = 65536;
def SCRATCHSZ: size = 1024;
def MAXNAME: size = 32;
def MAXENV: size = 16;
def MAXVAL: size = 64;
def MAXALIAS: size = 16;
def ALIASLEN: size = 128;
def MAXHIST: size = 32;
def HISTLEN: size = 128;
def LINEMAX: size = 128;
def EXPMAX: size = 256;
def MAXDEPTH: size = 16;
def NOFOUND: size = ~0z;

// Storage for unescaping a line and for rewriting a file to append to it.
let arena: [ARENASZ]u8 = [0...];
let scratch: [SCRATCHSZ]u8 = [0...];

let extprog_count: size = 0;
let extprog_names: [MAXEXTPROG][MAXNAME]u8 = [[0...]...];

// The environment the shell keeps for itself. A program started from here
// sees the filesystem but not these: there is nowhere to hand them over.
let env_names: [MAXENV][MAXNAME]u8 = [[0...]...];
let env_vals: [MAXENV][MAXVAL]u8 = [[0...]...];
let env_count: size = 0;

// Aliases: a name and the text it stands for.
let alias_names: [MAXALIAS][MAXNAME]u8 = [[0...]...];
let alias_vals: [MAXALIAS][ALIASLEN]u8 = [[0...]...];
let alias_count: size = 0;

// The commands that have been run, oldest first. The arrow keys walk them.
let hist: [MAXHIST][HISTLEN]u8 = [[0...]...];
let hist_len: [MAXHIST]size = [0...];
let hist_count: size = 0;
let hist_pos: size = 0;

// The directory the process was in before the last cd, so that "cd -" can
// go back to it.
let prevdir: [512]u8 = [0...];
let prevlen: size = 0;

// A stack of directories, for pushd and popd.
def MAXDIRS: size = 16;
let dirstack: [MAXDIRS][512]u8 = [[0...], [0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...],
	[0...], [0...]];
let dirlens: [MAXDIRS]size = [0...];
let ndirs: size = 0;

// A command line with an alias put in it.
let expbuf: [EXPMAX]u8 = [0...];

// A command line with the names that match a pattern put in it, and the
// names themselves on the way.
let globbuf: [EXPMAX]u8 = [0...];
let namesbuf: [EXPMAX]u8 = [0...];

// Paths built while a tree is being walked. There is one for each level, so
// a path being looked at is not overwritten by the one being built below it.
let treepaths: [MAXDEPTH][512]u8 = [[0...], [0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...],
	[0...], [0...]];

// What each command does, whether the shell knows it, and whether it takes
// paths, and so wants a name with a * in it looked for.
type entry = struct {
	name: str,
	help: str,
	builtin: bool,
	paths: bool,
};

const MANUAL: [71]entry = [
	entry { name = "cat", help = "print files", builtin = true , paths = true },
	entry { name = "cd", help = "move to another directory", builtin = true , paths = false },
	entry { name = "pwd", help = "say where this is", builtin = true , paths = false },
	entry { name = "ls", help = "list a directory", builtin = false , paths = true },
	entry { name = "echo", help = "say a line back", builtin = true , paths = false },
	entry { name = "write", help = "write a file, -a to append", builtin = true , paths = true },
	entry { name = "mkdir", help = "make a directory, -p for its parents", builtin = true , paths = true },
	entry { name = "touch", help = "make an empty file", builtin = true , paths = true },
	entry { name = "rm", help = "remove a file, -r for a whole tree", builtin = true , paths = true },
	entry { name = "hd", help = "dump a file in hex", builtin = true , paths = true },
	entry { name = "cc", help = "compile and link a C program", builtin = true , paths = true },
	entry { name = "env", help = "list the environment", builtin = true , paths = false },
	entry { name = "export", help = "set an environment variable", builtin = true , paths = false },
	entry { name = "unset", help = "remove an environment variable", builtin = true , paths = false },
	entry { name = "alias", help = "name a command for something else", builtin = true , paths = false },
	entry { name = "unalias", help = "forget an alias", builtin = true , paths = false },
	entry { name = "history", help = "list the commands that have been run", builtin = true , paths = false },
	entry { name = "which", help = "say where a command is", builtin = true , paths = false },
	entry { name = "man", help = "say what a command does", builtin = true , paths = false },
	entry { name = "uptime", help = "say how long the machine has been up", builtin = true , paths = false },
	entry { name = "free", help = "say how much memory is left", builtin = true , paths = false },
	entry { name = "sleep", help = "wait for a number of seconds", builtin = true , paths = false },
	entry { name = "clear", help = "clear the screen", builtin = true , paths = false },
	entry { name = "true", help = "do nothing, and succeed", builtin = true , paths = false },
	entry { name = "false", help = "do nothing, and fail", builtin = true , paths = false },
	entry { name = "user", help = "start a program of its own", builtin = true , paths = false },
	entry { name = "multi", help = "start three programs at once", builtin = true , paths = false },
	entry { name = "version", help = "say what this is", builtin = true , paths = false },
	entry { name = "help", help = "say what can be done", builtin = true , paths = false },
	entry { name = "tutorial", help = "a walk through the system", builtin = true , paths = false },
	entry { name = "exit", help = "leave the shell", builtin = true , paths = false },
	entry { name = "halt", help = "stop the machine", builtin = true , paths = false },
	entry { name = "poweroff", help = "stop the machine", builtin = true , paths = false },
	entry { name = "sort", help = "sort the lines: -n numbers, -r back, -u one of each", builtin = false , paths = true },
	entry { name = "uniq", help = "drop the lines that repeat", builtin = false , paths = true },
	entry { name = "head", help = "the first lines: -n N or -N", builtin = false , paths = true },
	entry { name = "tail", help = "the last lines: -n N or -N", builtin = false , paths = true },
	entry { name = "tr", help = "translate characters, as in a-z, or -d to drop", builtin = false , paths = true },
	entry { name = "rev", help = "turn the lines of a file around", builtin = false , paths = true },
	entry { name = "seq", help = "print a run of numbers", builtin = false , paths = false },
	entry { name = "expr", help = "do arithmetic", builtin = false , paths = false },
	entry { name = "basename", help = "the last part of a path", builtin = false , paths = false },
	entry { name = "dirname", help = "the directory a path is in", builtin = false , paths = false },
	entry { name = "stat", help = "say what a path is", builtin = false , paths = true },
	entry { name = "du", help = "say how big a tree is", builtin = false , paths = true },
	entry { name = "df", help = "say how much room is left", builtin = false , paths = false },
	entry { name = "test", help = "ask about a path", builtin = false , paths = true },
	entry { name = "find", help = "look for a name in a tree: -name pattern", builtin = false , paths = true },
	entry { name = "tree", help = "print a tree", builtin = false , paths = true },
	entry { name = "wc", help = "count lines, words and bytes: -l -w -c", builtin = false , paths = true },
	entry { name = "grep", help = "print lines holding a pattern: -i -v -n -c", builtin = false , paths = true },
	entry { name = "cp", help = "copy: -r a tree, or many files to a directory", builtin = false , paths = true },
	entry { name = "mv", help = "move a file", builtin = false , paths = true },
	entry { name = "nl", help = "number the lines of a file", builtin = false , paths = true },
	entry { name = "cut", help = "take parts of each line", builtin = false , paths = true },
	entry { name = "paste", help = "put files side by side", builtin = false , paths = true },
	entry { name = "comm", help = "three columns of two sorted files: -1 -2 -3", builtin = false , paths = true },
	entry { name = "diff", help = "what is different between two files", builtin = false , paths = true },
	entry { name = "od", help = "dump a file in octal and hex", builtin = false , paths = true },
	entry { name = "strings", help = "the printable parts of a file", builtin = false , paths = true },
	entry { name = "cksum", help = "a checksum of a file", builtin = false , paths = true },
	entry { name = "file", help = "say what a file is", builtin = false , paths = true },
	entry { name = "uname", help = "the machine this is", builtin = false , paths = false },
	entry { name = "id", help = "which process this is", builtin = false , paths = false },
	entry { name = "split", help = "split a file into pieces: -l lines, a name", builtin = false , paths = true },
	entry { name = "ps", help = "the processes that are running", builtin = false , paths = false },
	entry { name = "kill", help = "stop a process", builtin = false , paths = false },
	entry { name = "install", help = "put Bunix on a disk", builtin = false , paths = false },
	entry { name = "type", help = "say what a command is", builtin = true , paths = false },
	entry { name = "pushd", help = "remember a directory and move", builtin = true , paths = true },
	entry { name = "popd", help = "go back to a remembered directory", builtin = true , paths = false },
];

fn load_bin() void = {
	let buf: [512]u8 = [0...];
	const n = rt::readdir("/bin", buf[..]);
	if (n == 0) {
		return;
	};
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			const l = i - start;
			if (l > 0 && l < MAXNAME && extprog_count < MAXEXTPROG) {
				for (let j = 0z; j < l; j += 1) {
					extprog_names[extprog_count][j] = buf[start + j];
				};
				extprog_names[extprog_count][l] = 0;
				extprog_count += 1;
			};
			start = i + 1;
		};
	};
};

fn is_extprog(cmd: []u8) bool = {
	for (let i = 0z; i < extprog_count; i += 1) {
		let ok = true;
		for (let j = 0z; j < len(cmd); j += 1) {
			if (extprog_names[i][j] != cmd[j]) {
				ok = false;
				break;
			};
		};
		if (ok && extprog_names[i][len(cmd)] == 0) {
			return true;
		};
	};
	return false;
};

fn help_extprog() void = {
	for (let i = 0z; i < extprog_count; i += 1) {
		rt::print(" ");
		let j = 0z;
		for (extprog_names[i][j] != 0) {
			rt::putc(extprog_names[i][j]);
			j += 1;
		};
	};
	rt::println("");
};

export @symbol("main") fn main() void = {
	const a = rt::arg();
	if (len(a) == 0) {
		rt::println("usage: cat <path>");
		return;
	};

	if (rt::strcmp(a, "/heap")) {
		let b: []u8 = [];
		for (let i = 0z; i < 8; i += 1) {
			append(b, ('A': u8) + (i: u8))!;
		};
		rt::print("heap: ");
		rt::write(b);
		rt::println("");
		free(b);
		return;
	};

	if (rt::strcmp(a, "/bad")) {
		rt::println("touching supervisor memory");
		const addr = 0x100000: uintptr;
		const p = addr: *u64;
		*p = 1;
		rt::println("should not reach here");
		return;
	};

	if (rt::strcmp(a, "/cons")) {
		const s: str = "written through /dev/cons\n";
		_ = rt::writefile("/dev/cons", *(&s: *[]u8));
		return;
	};

	if (rt::strcmp(a, "/note")) {
		const s: str = "a note from a user process\n";
		_ = rt::writefile("/dev/note", *(&s: *[]u8));
		let out: [256]u8 = [0...];
		const k = rt::readfile("/dev/note", out[..]);
		rt::print("note: ");
		rt::write(out[..k]);
		return;
	};

	if (rt::strcmp(a, "/ns")) {
		rt::println("namespace view of / :");
		let out: [256]u8 = [0...];
		let k = rt::readfile("/", out[..]);
		rt::write(out[..k]);
		const marker: str = "sealed with a private marker\n";
		_ = rt::create("/pp");
		_ = rt::writefile("/pp", *(&marker: *[]u8));
		k = rt::readfile("/pp", out[..]);
		rt::print("read back: ");
		rt::write(out[..k]);
		k = rt::readfile("/hello", out[..]);
		rt::print("shared /hello bytes: ");
		rt::printnum(k: u64);
		rt::println("");
		k = rt::readfile("/proc/self", out[..]);
		rt::print("this process: ");
		rt::write(out[..k]);
		return;
	};

	if (rt::strcmp(a, "/disk")) {
		let out: [512]u8 = [0...];
		const k = rt::readfile("/dev/disk", out[..]);
		rt::print("sector 0 holds ");
		rt::printnum(k: u64);
		rt::print(" bytes: ");
		let n = 0z;
		for (n < k && out[n] != ('\n': u8) && out[n] != 0) {
			rt::putc(out[n]);
			n += 1;
		};
		rt::println("");
		return;
	};

	if (starts(a, "/spin ")) {
		for (let i = 0u64; i < 4; i += 1) {
			rt::print(a);
			rt::print(" step ");
			rt::printnum(i);
			rt::println("");
			for (let j = 0u64; j < 4000000; j += 1) {
				void;
			};
		};
		return;
	};

	if (rt::strcmp(a, "/sh")) {
		rt::println("bunix user shell, type 'help'");
		load_bin();
		shell();
		return;
	};

	let buf: [256]u8 = [0...];
	const n = rt::readfile(a, buf[..]);
	if (n == 0) {
		rt::print("cat: cannot read ");
		rt::println(a);
		return;
	};
	rt::write(buf[..n]);
};

// The prompt, and the loop that goes with it.
fn shell() void = {
	for (true) {
		rt::print("ush> ");
		let lb: [LINEMAX]u8 = [0...];
		const n = read_line(lb[..]);
		if (n == 0) {
			continue;
		};
		if (!run_line(lb[..n])) {
			break;
		};
	};
};

// Where the output of a command is sent, when the line says so with a ">"
// or a ">>" at the end of it.
type redirect = struct {
	mark: size,
	add: bool,
};

// Looks for the mark that sends the output of a command to a file. The mark
// has to be outside of quotes, so that a file name may have one in it.
fn find_redirect(line: []u8, r: *redirect) bool = {
	r.mark = 0;
	r.add = false;
	let quote = 0u8;
	for (let i = 0z; i < len(line); i += 1) {
		const c = line[i];
		if (quote != 0) {
			if (c == quote) {
				quote = 0;
			};
			continue;
		};
		if (c == ('"': u8) || c == ('\'': u8)) {
			quote = c;
			continue;
		};
		if (c == ('>': u8)) {
			r.mark = i;
			r.add = i + 1 < len(line) && line[i + 1] == ('>': u8);
			return true;
		};
	};
	return false;
};

// Takes the quotes off a word, when it has them.
fn strip_quotes(word: str) str = {
	const b = *(&word: *[]u8);
	if (len(b) >= 2) {
		if ((b[0] == ('"': u8) && b[len(b) - 1] == ('"': u8))
				|| (b[0] == 39 && b[len(b) - 1] == 39)) {
			return *(&b[1..len(b) - 1]: *str);
		};
	};
	return word;
};

// Runs one line of input. The alias is put in first, then the command is
// looked up. It says whether the shell should keep going.
fn run_line(line: []u8) bool = {
	hist_add(line);
	const expanded = expand_alias(line);
	return run_pipe(expanded, expanded[0..0], 0);
};

def MAXPIPE: size = 8;
const NOBAR: size = ~0z;

// Runs a line that may be a pipeline. A pipe is a file: the command on the
// left writes to a file of its own, and the command on the right is given
// that file, so that the left one has finished before the right one starts.
// That is not what a pipe does on a system where the two run at once, but
// the file is real and the filters work.
fn run_pipe(line: []u8, input: []u8, depth: size) bool = {
	const bar = find_bar(line);
	if (bar == NOBAR) {
		if (len(input) == 0) {
			return run_one(line);
		};
		// The command is given the file the one before it wrote.
		let buf: [512]u8 = [0...];
		const n = put_input(buf[..], line, input);
		return run_one(buf[..n]);
	};
	if (depth >= MAXPIPE) {
		rt::println("too many pipes");
		return true;
	};
	const left = line[..bar];
	let right = line[bar + 1..];
	// The spaces after the pipe are not the name of a command.
	for (len(right) > 0 && (right[0] == (' ': u8) || right[0] == ('\t': u8))) {
		right = right[1..];
	};
	// Each pipe has a file of its own, so that a line with more than one
	// pipe in it does not write over what it is reading.
	let name: [24]u8 = [0...];
	const pn = pipe_name(name[..], depth);
	if (!rt::redirect(*(&name[..pn]: *str), false)) {
		rt::println("cannot make the pipe");
		return true;
	};
	const ok = run_pipe(left, input, depth);
	rt::redirect("", false);
	const more = run_pipe(right, name[..pn], depth + 1);
	_ = rt::remove(*(&name[..pn]: *str));
	return ok && more;
};

// Where the pipe between two commands is, or NOBAR when there is none. A
// pipe in quotes is part of a word, and not a pipe.
fn find_bar(line: []u8) size = {
	let quote = 0u8;
	for (let i = 0z; i < len(line); i += 1) {
		const c = line[i];
		if (quote != 0) {
			if (c == quote) {
				quote = 0;
			};
			continue;
		};
		if (c == ('"': u8) || c == ('\'': u8)) {
			quote = c;
			continue;
		};
		if (c == ('|': u8)) {
			return i;
		};
	};
	return NOBAR;
};

// The name of the file a command in a pipeline writes to. It is a file like
// any other, and it sits with the other files the system makes for itself.
fn pipe_name(buf: []u8, depth: size) size = {
	const prefix = *(&"/dev/pipe": *[]u8);
	let n = 0z;
	for (let i = 0z; i < len(prefix) && n < len(buf); i += 1) {
		buf[n] = prefix[i];
		n += 1;
	};
	if (n < len(buf)) {
		const d: u8 = (depth % 10): u8;
		buf[n] = ('0': u8) + d;
		n += 1;
	};
	return n;
};

// A line with the file a command is given put in it. The file goes before
// a >, so that the name of the file the output goes to is still taken for
// the name of the file, and not for another argument.
fn put_input(buf: []u8, line: []u8, input: []u8) size = {
	let r = redirect { mark = 0, add = false };
	let cut = len(line);
	if (find_redirect(line, &r) && r.mark != 0) {
		cut = r.mark;
	};
	let n = 0z;
	for (let i = 0z; i < cut && n < len(buf); i += 1) {
		buf[n] = line[i];
		n += 1;
	};
	if (n < len(buf)) {
		buf[n] = (' ': u8);
		n += 1;
	};
	for (let i = 0z; i < len(input) && n < len(buf); i += 1) {
		buf[n] = input[i];
		n += 1;
	};
	if (cut < len(line) && n < len(buf)) {
		buf[n] = (' ': u8);
		n += 1;
	};
	for (let i = cut; i < len(line) && n < len(buf); i += 1) {
		buf[n] = line[i];
		n += 1;
	};
	return n;
};

// Runs one command, and sends its output to a file when it was told to.
fn run_one(line: []u8) bool = {
	// The output of the command may be sent to a file instead of the
	// screen. The mark is looked for before the command is run, so that
	// the file is made even when the command itself is not there.
	let r = redirect { mark = 0, add = false };
	if (!find_redirect(line, &r) || r.mark == 0) {
		return run_command(line);
	};
	// The name of the file is what is left, without the spaces around it.
	const skip: size = if (r.add) 2 else 1;
	let name = line[r.mark + skip..];
	let start = 0z;
	for (let i = 0z; i < len(name); i += 1) {
		if (name[i] != (' ': u8) && name[i] != ('\t': u8)) {
			start = i;
			break;
		};
	};
	let end = 0z;
	for (let i = 0z; i < len(name); i += 1) {
		if (name[i] != (' ': u8) && name[i] != ('\t': u8)) {
			end = i + 1;
		};
	};
	name = name[start..end];
	if (len(name) == 0) {
		rt::println("usage: command > file");
		return true;
	};
	const path = strip_quotes(*(&name: *str));
	if (!rt::redirect(path, r.add)) {
		rt::print("cannot write to ");
		rt::println(path);
		return true;
	};
	const ok = run_command(line[..r.mark]);
	// The output goes back to the screen.
	rt::redirect("", false);
	return ok;
};

// Runs a command. The line has its alias put in already.
fn run_command(line: []u8) bool = {
	const sp = lib::first_space(line);
	const cmd = line[..sp];
	const rest = if (sp < len(line)) line[sp + 1..] else line[0..0];
	// A line with nothing to run on it, as when a pipe has nothing after
	// it, is not a command that could not be found.
	if (len(cmd) == 0) {
		return true;
	};
	if (str_eq(cmd, "exit")) {
		rt::println("bye");
		return false;
	} else if (str_eq(cmd, "help")) {
		run_help();
	} else if (str_eq(cmd, "tutorial")) {
		run_tutorial(rest);
	} else if (str_eq(cmd, "version")) {
		const vp: str = "/proc/version";
		run_cat(*(&vp: *[]u8));
	} else if (str_eq(cmd, "echo")) {
		// The spaces at the end are not part of what is said, which
		// matters when the line was cut where a > began.
		let end = len(rest);
		for (end > 0 && (rest[end - 1] == (' ': u8)
				|| rest[end - 1] == ('\t': u8))) {
			end -= 1;
		};
		let said = rest[..end];
		// Quotes around the whole of it are not part of what is said.
		if (len(said) >= 2 && ((said[0] == ('"': u8)
				&& said[len(said) - 1] == ('"': u8))
				|| (said[0] == 39 && said[len(said) - 1] == 39))) {
			said = said[1..len(said) - 1];
		};
		rt::write(said);
		rt::println("");
	} else if (str_eq(cmd, "cat")) {
		run_cat(expand_glob(rest));
	} else if (str_eq(cmd, "cd")) {
		run_cd(rest);
	} else if (str_eq(cmd, "pushd")) {
		run_pushd(rest);
	} else if (str_eq(cmd, "popd")) {
		run_popd();
	} else if (str_eq(cmd, "pwd")) {
		rt::println(rt::getcwd());
	} else if (str_eq(cmd, "type")) {
		run_type(rest);
	} else if (str_eq(cmd, "clear")) {
		out("\x1b[2J\x1b[H");
	} else if (str_eq(cmd, "env")) {
		run_env();
	} else if (str_eq(cmd, "export")) {
		run_export(rest);
	} else if (str_eq(cmd, "unset")) {
		run_unset(rest);
	} else if (str_eq(cmd, "alias")) {
		run_alias(rest);
	} else if (str_eq(cmd, "unalias")) {
		run_unalias(rest);
	} else if (str_eq(cmd, "history")) {
		run_history();
	} else if (str_eq(cmd, "which")) {
		run_which(rest);
	} else if (str_eq(cmd, "man")) {
		run_man(rest);
	} else if (str_eq(cmd, "uptime")) {
		rt::print("up ");
		rt::printnum(uptime_secs());
		rt::println(" seconds");
	} else if (str_eq(cmd, "free")) {
		let fb: [128]u8 = [0...];
		const k = rt::readfile("/proc/mem", fb[..]);
		rt::write(fb[..k]);
	} else if (str_eq(cmd, "sleep")) {
		run_sleep(rest);
	} else if (str_eq(cmd, "true")) {
		// Nothing to do, and nothing went wrong.
		void;
	} else if (str_eq(cmd, "false")) {
		// Nothing to do, and something did go wrong.
		void;
	} else if (str_eq(cmd, "write")) {
		run_write(rest);
	} else if (str_eq(cmd, "hd")) {
		run_hd(rest);
	} else if (str_eq(cmd, "cc")) {
		run_cc(rest);
	} else if (str_eq(cmd, "mkdir")) {
		run_mkdir(rest);
	} else if (str_eq(cmd, "touch")) {
		report(rt::create(*(&rest: *str)), "created", "cannot create");
	} else if (str_eq(cmd, "rm")) {
		run_rm(rest);
	} else if (is_extprog(cmd)) {
		// external program with an image of its own
		run(glob_for(cmd, line));
	} else if (is_path(cmd)) {
		// a path into the filesystem: the loader decides whether it
		// is an executable to run or a file to read
		run(glob_for(cmd, line));
	} else if (str_eq(cmd, "user")) {
		const pid = rt::spawn(*(&rest: *str));
		if (pid == ~0u64) {
			rt::println("cannot spawn");
		} else {
			for (rt::alive(pid)) {
				rt::cop();
			};
			rt::println("user process exited");
		};
	} else if (str_eq(cmd, "multi")) {
		run_multi();
	} else if (str_eq(cmd, "halt") || str_eq(cmd, "poweroff")) {
		rt::print("halting. ");
		rt::haltsys();
	} else {
		rt::print("unknown command: ");
		rt::println(*(&cmd: *str));
	};
	return true;
};

fn starts(s: str, p: str) bool = {
	const b = *(&s: *[]u8);
	const pb = *(&p: *[]u8);
	if (len(b) < len(pb)) {
		return false;
	};
	for (let i = 0z; i < len(pb); i += 1) {
		if (b[i] != pb[i]) {
			return false;
		};
	};
	return true;
};

// Run a program in an image of its own and wait for it. The loader picks the
// image by the first word of the line.
fn run(line: []u8) void = {
	const pid = rt::spawn_shared(*(&line: *str));
	if (pid == ~0u64) {
		rt::println("cannot run");
		return;
	};
	for (rt::alive(pid)) {
		rt::cop();
	};
};

fn report(ok: bool, yes: str, no: str) void = {
	if (ok) {
		rt::println(yes);
	} else {
		rt::println(no);
	};
};

// A command naming something in the filesystem rather than a built-in. The
// loader decides whether it is an executable to run or a file to read.
fn is_path(cmd: []u8) bool = {
	if (len(cmd) == 0 || cmd[0] != ('/': u8)) {
		return false;
	};
	return rt::exists(*(&cmd: *str));
};

fn str_eq(b: []u8, s: str) bool = {
	const sb = *(&s: *[]u8);
	if (len(b) != len(sb)) {
		return false;
	};
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] != sb[i]) {
			return false;
		};
	};
	return true;
};

// Whether two sets of bytes are the same.
fn eqb(a: []u8, b: []u8) bool = {
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

// Whether a name held in a fixed array is the same as a string. The array is
// longer than the name, with zeros after it, so only the name is compared.
fn eqname(held: []u8, name: []u8) bool = {
	const n = namelen(held);
	if (n != len(name)) {
		return false;
	};
	for (let i = 0z; i < n; i += 1) {
		if (held[i] != name[i]) {
			return false;
		};
	};
	return true;
};

// Writes a string to the console.
fn out(s: str) void = {
	rt::write(*(&s: *[]u8));
};

// Prints one file, or several one after another.
fn run_cat(rest: []u8) void = {
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(rest, &words);
	if (n == 0) {
		rt::println("usage: cat <path>...");
		return;
	};
	for (let i = 0z; i < n; i += 1) {
		const path = words[i];
		let buf: [512]u8 = [0...];
		const k = rt::readfile(*(&path: *str), buf[..]);
		if (k == 0) {
			rt::print("cat: cannot read ");
			rt::println(*(&path: *str));
			continue;
		};
		rt::write(buf[..k]);
		if (buf[k - 1] != ('\n': u8)) {
			rt::println("");
		};
	};
};

// Moves to another directory. With no name it goes back to the top.
fn run_cd(rest: []u8) void = {
	// With no name it goes back to the top, and with a dash it goes back
	// to where it was before.
	if (len(rest) == 0) {
		do_cd("/");
		return;
	};
	if (len(rest) == 1 && rest[0] == ('-': u8)) {
		if (prevlen == 0) {
			rt::println("cd: no previous directory");
			return;
		};
		do_cd(*(&prevdir[..prevlen]: *str));
		return;
	};
	do_cd(*(&rest: *str));
};

// Moves to a directory, remembering where it was.
fn do_cd(path: str) void = {
	// Where it is now, so that a dash can go back to it.
	const here = rt::getcwd();
	const hb = *(&here: *[]u8);
	prevlen = 0;
	for (let i = 0z; i < len(hb) && i < len(prevdir); i += 1) {
		prevdir[i] = hb[i];
		prevlen = i + 1;
	};
	if (!rt::chdir(path)) {
		rt::print("cd: no such directory: ");
		rt::println(path);
	};
};

// Puts the directory it is in on a stack and moves somewhere else.
fn run_pushd(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: pushd <path>");
		return;
	};
	if (ndirs >= MAXDIRS) {
		rt::println("pushd: the stack is full");
		return;
	};
	const here = rt::getcwd();
	const hb = *(&here: *[]u8);
	let n = 0z;
	for (let i = 0z; i < len(hb) && n + 1 < len(dirstack[ndirs]); i += 1) {
		dirstack[ndirs][n] = hb[i];
		n += 1;
	};
	dirlens[ndirs] = n;
	ndirs += 1;
	do_cd(*(&rest: *str));
	rt::println(*(&dirstack[ndirs - 1][..dirlens[ndirs - 1]]: *str));
};

// Takes the last directory off the stack and goes back to it.
fn run_popd() void = {
	if (ndirs == 0) {
		rt::println("popd: the stack is empty");
		return;
	};
	ndirs -= 1;
	const p = *(&dirstack[ndirs][..dirlens[ndirs]]: *str);
	do_cd(p);
	rt::println(p);
};

// What a command is: a command of the shell, a program, or a file.
fn run_type(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: type <command>");
		return;
	};
	const sp = lib::first_space(rest);
	const cmd = rest[..sp];
	const i = manual_find(cmd);
	if (i != NOFOUND && MANUAL[i].builtin) {
		rt::write(cmd);
		rt::println(": a command of the shell");
		return;
	};
	if (is_extprog(cmd)) {
		rt::write(cmd);
		rt::println(": a program, in /bin");
		return;
	};
	if (rt::exists(*(&cmd: *str))) {
		rt::write(cmd);
		rt::println(": a file");
		return;
	};
	rt::print("type: not found: ");
	rt::println(*(&cmd: *str));
};

// The environment, one variable to a line.
fn run_env() void = {
	for (let i = 0z; i < env_count; i += 1) {
		rt::print(namestr(env_names[i][..]));
		rt::print("=");
		rt::println(namestr(env_vals[i][..]));
	};
};

// Sets an environment variable.
fn run_export(rest: []u8) void = {
	if (len(rest) == 0) {
		run_env();
		return;
	};
	const eq = find_char(rest, ('=': u8));
	if (eq == NOFOUND) {
		rt::println("usage: export NAME=VALUE");
		return;
	};
	env_set(rest[..eq], rest[eq + 1..]);
};

// Removes an environment variable.
fn run_unset(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: unset NAME");
		return;
	};
	for (let i = 0z; i < env_count; i += 1) {
		if (!eqname(env_names[i][..], rest)) {
			continue;
		};
		// The ones after it move down, so the list stays packed.
		for (let j = i + 1; j < env_count; j += 1) {
			copy_str(env_names[j - 1][..], env_names[j][..]);
			copy_str(env_vals[j - 1][..], env_vals[j][..]);
		};
		env_count -= 1;
		return;
	};
	rt::print("unset: not set: ");
	rt::println(*(&rest: *str));
};

// Names a command for something else.
fn run_alias(rest: []u8) void = {
	if (len(rest) == 0) {
		for (let i = 0z; i < alias_count; i += 1) {
			rt::print(namestr(alias_names[i][..]));
			rt::print("=");
			rt::println(namestr(alias_vals[i][..]));
		};
		return;
	};
	const eq = find_char(rest, ('=': u8));
	if (eq == NOFOUND) {
		// A name on its own says what it stands for.
		const i = alias_find(rest);
		if (i == NOFOUND) {
			rt::print("alias: not an alias: ");
			rt::println(*(&rest: *str));
			return;
		};
		rt::print(namestr(alias_names[i][..]));
		rt::print("=");
		rt::println(namestr(alias_vals[i][..]));
		return;
	};
	alias_set(rest[..eq], rest[eq + 1..]);
};

// Forgets an alias.
fn run_unalias(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: unalias NAME");
		return;
	};
	const i = alias_find(rest);
	if (i == NOFOUND) {
		rt::print("unalias: not an alias: ");
		rt::println(*(&rest: *str));
		return;
	};
	for (let j = i + 1; j < alias_count; j += 1) {
		copy_str(alias_names[j - 1][..], alias_names[j][..]);
		copy_str(alias_vals[j - 1][..], alias_vals[j][..]);
	};
	alias_count -= 1;
};

// The commands that have been run, oldest first.
fn run_history() void = {
	for (let i = 0z; i < hist_count; i += 1) {
		rt::printnum((i + 1): u64);
		rt::print("  ");
		rt::println(namestr(hist[i][..hist_len[i]]));
	};
};

// Where a command is: a command of the shell's own, a program, or a path.
fn run_which(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: which <command>");
		return;
	};
	const sp = lib::first_space(rest);
	const cmd = rest[..sp];
	const i = manual_find(cmd);
	if (i != NOFOUND && MANUAL[i].builtin) {
		rt::write(cmd);
		rt::println(": a command of the shell");
		return;
	};
	if (is_extprog(cmd)) {
		rt::write(cmd);
		rt::print(": /bin/");
		rt::write(cmd);
		rt::println("");
		return;
	};
	if (rt::exists(*(&cmd: *str))) {
		rt::write(cmd);
		rt::println("");
		return;
	};
	rt::print("which: not found: ");
	rt::println(*(&cmd: *str));
};

// What a command does.
fn run_man(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: man <command>");
		return;
	};
	const sp = lib::first_space(rest);
	const cmd = rest[..sp];
	const i = manual_find(cmd);
	if (i == NOFOUND) {
		rt::print("man: nothing known about ");
		rt::println(*(&cmd: *str));
		return;
	};
	rt::print(MANUAL[i].name);
	rt::print(" - ");
	rt::println(MANUAL[i].help);
};

// What can be done.
fn run_help() void = {
	rt::println("bunix shell. The commands are:");
	for (let i = 0z; i < len(MANUAL); i += 1) {
		if (!MANUAL[i].builtin) {
			continue;
		};
		rt::print("  ");
		rt::print(MANUAL[i].name);
		rt::print(" - ");
		rt::println(MANUAL[i].help);
	};
	rt::println("and the programs:");
	help_extprog();
	rt::println("The up and down arrows walk the history, and the left and");
	rt::println("right arrows move along the line.");
	rt::println("A > at the end of a line sends the output to a file, and a");
	rt::println(">> adds to what is already in it. A | sends it to a file the");
	rt::println("command after the | is given, as in cat /tmp/x | wc -l.");
	rt::println("Type tutorial for a walk through the system.");
};

// How many chapters the tutorial has, besides the opening page.
def CHAPTERS: size = 5;

// The tutorial, a page at a time, so that a page fits on the screen. With no
// chapter named it shows where to begin.
fn run_tutorial(rest: []u8) void = {
	let a = rest;
	for (len(a) > 0 && (a[0] == (' ': u8) || a[0] == ('\t': u8))) {
		a = a[1..];
	};
	let end = len(a);
	for (end > 0 && (a[end - 1] == (' ': u8) || a[end - 1] == ('\t': u8))) {
		end -= 1;
	};
	a = a[..end];
	if (len(a) == 0) {
		tut_page(0);
		return;
	};
	if (str_eq(a, "all")) {
		for (let p = 0z; p <= CHAPTERS; p += 1) {
			if (p > 0) {
				rt::println("");
			};
			tut_page(p);
		};
		return;
	};
	let n: u64 = 0;
	if (lib::number(a, &n) == 0 || n > (CHAPTERS: u64)) {
		rt::println("usage: tutorial [1-5|all]");
		return;
	};
	tut_page(n: size);
};

fn tut_page(p: size) void = {
	if (p == 0) {
		tut_intro();
	} else if (p == 1) {
		tut_where();
	} else if (p == 2) {
		tut_files();
	} else if (p == 3) {
		tut_find();
	} else if (p == 4) {
		tut_devices();
	} else {
		tut_machine();
	};
};

fn tut_intro() void = {
	rt::println("Bunix tutorial");
	rt::println("");
	rt::println("Bunix is a small Unix. It starts one program, the shell, and the");
	rt::println("shell is where you work. The one idea to keep is that everything");
	rt::println("you can name is a file: a directory, the disk, the kernel, the");
	rt::println("memory, even a pipe.");
	rt::println("");
	rt::println("Read a chapter with");
	rt::println("  tutorial 1    where you are");
	rt::println("  tutorial 2    files and directories");
	rt::println("  tutorial 3    finding things");
	rt::println("  tutorial 4    files that are not files");
	rt::println("  tutorial 5    programs and the machine");
	rt::println("  tutorial all  all five");
	rt::println("");
	rt::println("man <command> says what one command does.");
};

fn tut_where() void = {
	rt::println("1  where you are");
	rt::println("");
	rt::println("Every process has a working directory, and pwd says what it is.");
	rt::println("");
	rt::println("  ush> pwd");
	rt::println("  /");
	rt::println("");
	rt::println("cd moves it. A path that does not start with / is looked for from");
	rt::println("there. pushd remembers a directory and popd comes back to it.");
	rt::println("");
	rt::println("  ush> cd /tmp");
	rt::println("  ush> pwd");
	rt::println("  /tmp");
	rt::println("");
	rt::println("ls lists a directory. ls -l adds the size, or says it is a");
	rt::println("directory, and ls -R walks the whole tree.");
	rt::println("");
	rt::println("  ush> ls /dev");
	rt::println("  ush> ls -l /bin");
};

fn tut_files() void = {
	rt::println("2  files and directories");
	rt::println("");
	rt::println("write puts text in a file. It does not add a line end, so say \\n");
	rt::println("where you want one.");
	rt::println("");
	rt::println("  ush> write /tmp/note.txt \"one\\ntwo\\n\"");
	rt::println("  ush> cat /tmp/note.txt");
	rt::println("");
	rt::println("cat prints a file, mkdir makes a directory and touch an empty");
	rt::println("one. cp copies a file, cp -r a whole tree, and mv moves.");
	rt::println("");
	rt::println("  ush> mkdir /tmp/work");
	rt::println("  ush> cp /tmp/note.txt /tmp/work/copy.txt");
	rt::println("  ush> rm -r /tmp/work");
	rt::println("");
	rt::println("A name with a space in it goes in quotes.");
	rt::println("");
	rt::println("  ush> write \"/tmp/two words.txt\" \"hi\\n\"");
	rt::println("  ush> cat \"/tmp/two words.txt\"");
};

fn tut_find() void = {
	rt::println("3  finding things");
	rt::println("");
	rt::println("The small programs take a file and say something about it.");
	rt::println("");
	rt::println("  ush> wc -l /tmp/note.txt       how many lines");
	rt::println("  ush> head -2 /tmp/note.txt     the first two");
	rt::println("  ush> tail -2 /tmp/note.txt     the last two");
	rt::println("  ush> sort /tmp/note.txt        the lines in order");
	rt::println("  ush> grep one /tmp/note.txt    the lines holding one");
	rt::println("");
	rt::println("cut takes part of each line, and tr changes characters.");
	rt::println("");
	rt::println("  ush> cut -d \" \" -f 1 /tmp/note.txt");
	rt::println("  ush> tr a-z A-Z /tmp/note.txt");
	rt::println("");
	rt::println("A * in a name stands for any run of characters, and the shell");
	rt::println("looks for it before the program runs, so a command that takes");
	rt::println("paths can be given a pattern.");
	rt::println("");
	rt::println("  ush> ls /usr/include/std*.h");
	rt::println("  ush> find /usr/src -name \"*.c\"");
};

fn tut_devices() void = {
	rt::println("4  files that are not files");
	rt::println("");
	rt::println("Some files are made when you read them.");
	rt::println("");
	rt::println("  ush> cat /proc/mem      the memory");
	rt::println("  ush> cat /proc/uptime   seconds since it started");
	rt::println("  ush> hd /dev/bootsec    the boot sector, in hex");
	rt::println("");
	rt::println("The output of a command can go to a file instead of the screen,");
	rt::println("with > to start the file over and >> to add to it.");
	rt::println("");
	rt::println("  ush> ls /usr/include > /tmp/list");
	rt::println("  ush> wc -l /tmp/list");
	rt::println("");
	rt::println("A | is a pipe, and a pipe is a file: the command on the left");
	rt::println("writes it, and the command on the right is given it.");
	rt::println("");
	rt::println("  ush> cat /tmp/list | sort");
	rt::println("  ush> cat /tmp/list | grep std | wc -l");
};

fn tut_machine() void = {
	rt::println("5  programs and the machine");
	rt::println("");
	rt::println("A program with an image of its own is in /bin and is run by its");
	rt::println("name. The shell hands it the rest of the line, not its own name.");
	rt::println("");
	rt::println("  ush> sort -r /tmp/list");
	rt::println("");
	rt::println("The C compiler is part of the system.");
	rt::println("");
	rt::println("  ush> write /tmp/hi.c \"int puts();\\n\"");
	rt::println("  ush> write -a /tmp/hi.c \"int main(void){puts(\\\"hi\\\");}\\n\"");
	rt::println("  ush> cc -o /tmp/hi /tmp/hi.c");
	rt::println("  ush> /tmp/hi");
	rt::println("");
	rt::println("Some commands are about the machine: free for the memory, df for");
	rt::println("the disk, ps for the programs that are running.");
	rt::println("");
	rt::println("install puts Bunix on a disk and asks before it writes. halt");
	rt::println("stops it.");
};

// Waits for a number of seconds.
fn run_sleep(rest: []u8) void = {
	let secs: u64 = 0;
	if (lib::number(rest, &secs) == 0) {
		rt::println("usage: sleep <seconds>");
		return;
	};
	const target = uptime_secs() + secs;
	for (true) {
		if (uptime_secs() >= target) {
			break;
		};
		rt::cop();
	};
};

// The seconds since the machine started.
fn uptime_secs() u64 = {
	let buf: [64]u8 = [0...];
	const n = rt::readfile("/proc/uptime", buf[..]);
	let v: u64 = 0;
	for (let i = 0z; i < n; i += 1) {
		const c = buf[i];
		if (c < ('0': u8) || c > ('9': u8)) {
			break;
		};
		v = v * 10 + ((c - ('0': u8)): u64);
	};
	return v;
};

// Starts three programs at once.
fn run_multi() void = {
	let ids: [3]u64 = [0u64, 0u64, 0u64];
	for (let i = 0z; i < 3; i += 1) {
		let arg: [8]u8 = [0...];
		arg[0] = '/': u8;
		arg[1] = 's': u8;
		arg[2] = 'p': u8;
		arg[3] = 'i': u8;
		arg[4] = 'n': u8;
		arg[5] = ' ': u8;
		arg[6] = ('1': u8) + (i: u8);
		const s = *(&arg[..7]: *str);
		ids[i] = rt::spawn(s);
	};
	for (true) {
		let live = false;
		for (let i = 0z; i < 3; i += 1) {
			if (rt::alive(ids[i])) {
				live = true;
			};
		};
		if (!live) {
			break;
		};
		rt::cop();
	};
	rt::println("all user processes exited");
};

// Turns the escapes a person actually types at the shell into bytes. Without
// this, "write f "a\nb"" would store a backslash and an n.
fn unescape(src: []u8) []u8 = {
	let n = 0z;
	let i = 0z;
	for (i < len(src) && n < len(scratch); i += 1) {
		let c = src[i];
		if (c == ('\\': u8) && i + 1 < len(src)) {
			const e = src[i + 1];
			i += 1;
			if (e == ('n': u8)) {
				c = ('\n': u8);
			} else if (e == ('t': u8)) {
				c = ('\t': u8);
			} else if (e == ('r': u8)) {
				c = ('\r': u8);
			} else if (e == ('0': u8)) {
				c = 0;
			} else {
				c = e;
			};
		};
		scratch[n] = c;
		n += 1;
	};
	return scratch[..n];
};

// Append by rewriting: the filesystem's write always lands at offset zero, so
// the old bytes have to be carried along.
fn append_text(path: str, text: []u8) size = {
	const have = rt::readfile(path, arena[..]);
	let n = have;
	for (let i = 0z; i < len(text) && n < len(arena); i += 1) {
		arena[n] = text[i];
		n += 1;
	};
	return rt::writefile(path, arena[..n]);
};

// Writes a file, or adds to one that is already there.
fn run_write(rest: []u8) void = {
	let body = rest;
	let do_append = false;
	if (len(body) >= 3 && body[0] == ('-': u8) && body[1] == ('a': u8)
			&& (body[2] == (' ': u8) || body[2] == ('\t': u8))) {
		do_append = true;
		body = body[3..];
		for (len(body) > 0 && (body[0] == (' ': u8) || body[0] == ('\t': u8))) {
			body = body[1..];
		};
	};
	// The path is the first word of the line, and it can be in quotes so
	// that it can hold spaces in it.
	let path: []u8 = body[0..0];
	let raw: []u8 = body[0..0];
	if (len(body) > 0 && (body[0] == ('"': u8) || body[0] == 39)) {
		const q = body[0];
		let i = 1z;
		for (i < len(body) && body[i] != q) {
			i += 1;
		};
		path = body[1..i];
		// What is left is the text, without the space in front of it.
		let j = i + 1;
		for (j < len(body) && (body[j] == (' ': u8) || body[j] == ('\t': u8))) {
			j += 1;
		};
		raw = body[j..];
	} else {
		const w = lib::first_space(body);
		if (w == len(body)) {
			rt::println("usage: write [-a] <path> <text>");
			return;
		};
		path = body[..w];
		raw = body[w + 1..];
	};
	if (len(path) == 0) {
		rt::println("usage: write [-a] <path> <text>");
		return;
	};
	if (len(raw) >= 2) {
		const db = *(&raw: *[]u8);
		if ((db[0] == ('"': u8) && db[len(db) - 1] == ('"': u8))
				|| (db[0] == 39 && db[len(db) - 1] == 39)) {
			raw = raw[1..len(raw) - 1];
		};
	};
	const text = unescape(raw);
	let k = 0z;
	if (do_append) {
		k = append_text(*(&path: *str), text);
	} else {
		k = rt::writefile(*(&path: *str), text);
	};
	rt::print("wrote ");
	rt::printnum(k: u64);
	rt::println(" bytes");
};

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

// Decimal, for "hd <path> <offset>".
fn parse_num(s: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(s); i += 1) {
		if (s[i] < ('0': u8) || s[i] > ('9': u8)) {
			break;
		};
		n = n * 10 + (s[i] - ('0': u8));
	};
	return n;
};

// A hex dump, "hd <path> [offset]". Read through a heap window so it works on
// a file too large for a stack buffer, which is what a linked executable is.
fn run_hd(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: hd <path> [offset]");
		return;
	};
	const sp = lib::first_space(rest);
	const path = rest[..sp];
	let off = 0z;
	if (sp < len(rest)) {
		off = parse_num(rest[sp + 1..]);
	};
	const window = rt::page_alloc(16);
	if (window == 0) {
		rt::println("hd: out of memory");
		return;
	};
	const view = (window: *[65536]u8)[..];
	const n = rt::readfile(*(&path: *str), view);
	if (n == 0) {
		rt::println("no such file");
		return;
	};
	for (let i = off; i < n; i += 16) {
		rt::putc(hexdig((i >> 12): u8 & 0x0f));
		rt::putc(hexdig((i >> 8): u8 & 0x0f));
		rt::putc(hexdig((i >> 4): u8 & 0x0f));
		rt::putc(hexdig(i: u8 & 0x0f));
		rt::print(": ");
		for (let j = 0z; j < 16 && i + j < n; j += 1) {
			const b = view[i + j];
			rt::putc(hexdig(b >> 4));
			rt::putc(hexdig(b & 0x0f));
			rt::putc(' ');
		};
		rt::println("");
	};
};

// Append one piece onto the end of a buffer.
fn put_into(out: []u8, at: *size, s: []u8) void = {
	for (let i = 0z; i < len(s) && *at < len(out); i += 1) {
		out[*at] = s[i];
		*at = *at + 1;
	};
};

// The command line for the compiler inside Bunix. tcc links against our own
// startup objects and library and must not go looking for a host system, so the
// flags are spelled out once here rather than at every prompt.
fn cc_line(args: []u8) void = {
	const head: str = "tcc ";
	const flags: str = "-static -nostdlib -B/usr/lib -L/usr/lib -I/usr/include";
	const crt1: str = " /usr/lib/crt1.o";
	const crti: str = " /usr/lib/crti.o";
	const libc: str = " /usr/lib/libc.a";
	const crtn: str = " /usr/lib/crtn.o";
	let buf: [600]u8 = [0...];
	let n = 0z;
	put_into(buf[..], &n, *(&head: *[]u8));
	put_into(buf[..], &n, *(&flags: *[]u8));
	put_into(buf[..], &n, args);
	put_into(buf[..], &n, *(&crt1: *[]u8));
	put_into(buf[..], &n, *(&crti: *[]u8));
	put_into(buf[..], &n, *(&libc: *[]u8));
	put_into(buf[..], &n, *(&crtn: *[]u8));
	run(buf[..n]);
};

// cc [-o out] source...  compiles and links against the Bunix runtime.
fn run_cc(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: cc [-o outfile] file.c ...");
		return;
	};
	const gap: str = " ";
	let outp: [256]u8 = [0...];
	let outn = 0z;
	let srcs: [400]u8 = [0...];
	let n = 0z;
	let i = 0z;
	for (true) {
		for (i < len(rest) && (rest[i] == (' ': u8) || rest[i] == ('\t': u8))) {
			i += 1;
		};
		const start = i;
		for (i < len(rest) && rest[i] != (' ': u8) && rest[i] != ('\t': u8)) {
			i += 1;
		};
		if (start == i) {
			break;
		};
		const tok = rest[start..i];
		if (len(tok) > 2 && tok[0] == ('-': u8) && (tok[1] == ('o': u8) || tok[1] == ('O': u8))) {
			const v = tok[2..];
			let k = len(v);
			if (k > len(outp)) {
				k = len(outp);
			};
			for (let j = 0z; j < k; j += 1) {
				outp[j] = v[j];
			};
			outn = k;
			continue;
		};
		put_into(srcs[..], &n, tok);
		put_into(srcs[..], &n, *(&gap: *[]u8));
	};
	if (n == 0) {
		rt::println("cc: no input files");
		return;
	};
	let args: [600]u8 = [0...];
	let an = 0z;
	const dasho: str = "-o ";
	put_into(args[..], &an, *(&dasho: *[]u8));
	put_into(args[..], &an, outp[..outn]);
	put_into(args[..], &an, *(&gap: *[]u8));
	put_into(args[..], &an, srcs[..n]);
	cc_line(args[..an]);
};

// Makes a directory. With -p the directories above it are made as well.
fn run_mkdir(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: mkdir [-p] <path>");
		return;
	};
	let path = rest;
	let parents = false;
	if (len(path) >= 2 && path[0] == ('-': u8) && path[1] == ('p': u8)
			&& (len(path) == 2 || path[2] == (' ': u8) || path[2] == ('\t': u8))) {
		parents = true;
		path = path[2..];
		for (len(path) > 0 && (path[0] == (' ': u8) || path[0] == ('\t': u8))) {
			path = path[1..];
		};
	};
	if (len(path) == 0) {
		rt::println("usage: mkdir [-p] <path>");
		return;
	};
	if (parents) {
		if (mkdir_p(path)) {
			rt::println("created");
		} else {
			rt::println("cannot create");
		};
		return;
	};
	report(rt::mkdir(*(&path: *str)), "created", "cannot create");
};

// Removes a file, or with -r a whole tree of them.
fn run_rm(rest: []u8) void = {
	if (len(rest) == 0) {
		rt::println("usage: rm [-r] <path>");
		return;
	};
	let path = rest;
	let deep = false;
	if (len(path) >= 2 && path[0] == ('-': u8) && path[1] == ('r': u8)
			&& (len(path) == 2 || path[2] == (' ': u8) || path[2] == ('\t': u8))) {
		deep = true;
		path = path[2..];
		for (len(path) > 0 && (path[0] == (' ': u8) || path[0] == ('\t': u8))) {
			path = path[1..];
		};
	};
	if (len(path) == 0) {
		rt::println("usage: rm [-r] <path>");
		return;
	};
	if (deep) {
		report(remove_tree(path, 0), "removed", "cannot remove");
		return;
	};
	report(rt::remove(*(&path: *str)), "removed", "cannot remove");
};

// The environment, kept for the shell.
fn env_set(name: []u8, val: []u8) void = {
	for (let i = 0z; i < env_count; i += 1) {
		if (eqname(env_names[i][..], name)) {
			copy_str(env_vals[i][..], val);
			return;
		};
	};
	if (env_count >= MAXENV) {
		rt::println("export: no room for any more");
		return;
	};
	copy_str(env_names[env_count][..], name);
	copy_str(env_vals[env_count][..], val);
	env_count += 1;
};

// An alias, kept for the shell.
fn alias_set(name: []u8, val: []u8) void = {
	for (let i = 0z; i < alias_count; i += 1) {
		if (eqname(alias_names[i][..], name)) {
			copy_str(alias_vals[i][..], val);
			return;
		};
	};
	if (alias_count >= MAXALIAS) {
		rt::println("alias: no room for any more");
		return;
	};
	copy_str(alias_names[alias_count][..], name);
	copy_str(alias_vals[alias_count][..], val);
	alias_count += 1;
};

fn alias_find(name: []u8) size = {
	for (let i = 0z; i < alias_count; i += 1) {
		if (eqname(alias_names[i][..], name)) {
			return i;
		};
	};
	return NOFOUND;
};

fn manual_find(name: []u8) size = {
	for (let i = 0z; i < len(MANUAL); i += 1) {
		const b = *(&MANUAL[i].name: *[]u8);
		if (eqb(b, name)) {
			return i;
		};
	};
	return NOFOUND;
};

// Puts the text an alias stands for in place of the command. The rest of the
// line is left where it was.
fn expand_alias(line: []u8) []u8 = {
	const sp = lib::first_space(line);
	const cmd = line[..sp];
	const i = alias_find(cmd);
	if (i == NOFOUND) {
		return line;
	};
	let n = 0z;
	// The value is usually written in quotes, so that it can hold spaces.
	const v = unquote(alias_vals[i][..]);
	for (let k = 0z; k < len(v) && n < len(expbuf); k += 1) {
		expbuf[n] = v[k];
		n += 1;
	};
	if (sp < len(line)) {
		if (n > 0 && n < len(expbuf)) {
			expbuf[n] = (' ': u8);
			n += 1;
		};
		for (let k = sp + 1; k < len(line) && n < len(expbuf); k += 1) {
			expbuf[n] = line[k];
			n += 1;
		};
	};
	return expbuf[..n];
};

// A string with the quotes around it taken off, if it has any.
fn unquote(s: []u8) []u8 = {
	const n = namelen(s);
	if (n >= 2) {
		const q = s[0];
		if ((q == ('"': u8) || q == 39) && s[n - 1] == q) {
			return s[1..n - 1];
		};
	};
	return s[..n];
};

// Expands the names in a command line. A word with a * in it is replaced by
// the names that match it, and a word that matches nothing is left as it
// was, so the program can say that it cannot find it.
fn expand_glob(line: []u8) []u8 = {
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(line, &words);
	let out = 0z;
	let any = false;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (i > 0 && out < len(globbuf)) {
			globbuf[out] = (' ': u8);
			out += 1;
		};
		if (!lib::has_star(w)) {
			out += put_word(globbuf[out..], w);
			continue;
		};
		const cnt = glob_one(w);
		if (cnt == 0) {
			// Nothing matched, so the word stays as it was.
			out += put_word(globbuf[out..], w);
			continue;
		};
		for (let j = 0z; j < cnt && out < len(globbuf); j += 1) {
			globbuf[out] = namesbuf[j];
			out += 1;
		};
		any = true;
	};
	if (!any) {
		return line;
	};
	return globbuf[..out];
};

// A word put into a buffer, with quotes around it when it holds spaces, so
// that it is still one word when the line is split again.
fn put_word(buf: []u8, w: []u8) size = {
	let space = false;
	for (let j = 0z; j < len(w); j += 1) {
		if (w[j] == (' ': u8) || w[j] == ('\t': u8)) {
			space = true;
		};
	};
	let n = 0z;
	if (space && n < len(buf)) {
		buf[n] = ('"': u8);
		n += 1;
	};
	for (let j = 0z; j < len(w) && n < len(buf); j += 1) {
		buf[n] = w[j];
		n += 1;
	};
	if (space && n < len(buf)) {
		buf[n] = ('"': u8);
		n += 1;
	};
	return n;
};

// The names in a directory that match a pattern, written into namesbuf. The
// pattern is the last part of the word, and the directory is what comes
// before it. How many names there are is returned.
fn glob_one(word: []u8) size = {
	// The directory the names are in, the pattern itself, and the part of
	// the word that goes in front of a name.
	let dir: []u8 = *(&".": *[]u8);
	let pat = word;
	let prefix: []u8 = word[0..0];
	let slash = NOFOUND;
	for (let i = 0z; i < len(word); i += 1) {
		if (word[i] == ('/': u8)) {
			slash = i;
		};
	};
	if (slash != NOFOUND) {
		dir = if (slash == 0) *(&"/": *[]u8) else word[..slash];
		pat = word[slash + 1..];
		prefix = word[..slash + 1];
	};
	let buf: [1024]u8 = [0...];
	const n = rt::readdir(*(&dir: *str), buf[..]);
	if (n == 0) {
		return 0;
	};
	let cnt = 0z;
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				const name = buf[start..i];
				if (!lib::matches(name, pat)) {
					start = i + 1;
					continue;
				};
				// The names are separated by a space, so the caller can
				// take them one after another.
				if (cnt > 0 && cnt < len(namesbuf)) {
					namesbuf[cnt] = (' ': u8);
					cnt += 1;
				};
				for (let j = 0z; j < len(prefix) && cnt < len(namesbuf); j += 1) {
					namesbuf[cnt] = prefix[j];
					cnt += 1;
				};
				for (let j = 0z; j < len(name) && cnt < len(namesbuf); j += 1) {
					namesbuf[cnt] = name[j];
					cnt += 1;
				};
			};
			start = i + 1;
		};
	};
	return cnt;
};

// Expands the names in a command line, but only for a command that takes
// paths. The text of a write is not a path, and a * in it is just a *.
fn glob_for(cmd: []u8, line: []u8) []u8 = {
	const i = manual_find(cmd);
	if (i == NOFOUND || !MANUAL[i].paths) {
		return line;
	};
	return expand_glob(line);
};

// Remembers a command, so the arrow keys can bring it back.
fn hist_add(line: []u8) void = {
	if (len(line) == 0) {
		return;
	};
	// The same command twice running is not worth keeping.
	if (hist_count > 0) {
		const last = hist_count - 1;
		if (hist_len[last] == len(line) && eqb(hist[last][..hist_len[last]], line)) {
			return;
		};
	};
	if (hist_count == MAXHIST) {
		// The oldest one goes, to make room for the newest.
		for (let i = 0z; i + 1 < MAXHIST; i += 1) {
			for (let j = 0z; j < len(hist[i + 1]); j += 1) {
				hist[i][j] = hist[i + 1][j];
			};
			hist_len[i] = hist_len[i + 1];
		};
		hist_count -= 1;
	};
	let n = len(line);
	if (n > HISTLEN) {
		n = HISTLEN;
	};
	for (let i = 0z; i < n; i += 1) {
		hist[hist_count][i] = line[i];
	};
	hist_len[hist_count] = n;
	hist_count += 1;
};

// A command from the history, put into the line.
fn hist_copy(buf: []u8, i: size) size = {
	if (i >= hist_count) {
		return 0;
	};
	let n = hist_len[i];
	if (n > len(buf)) {
		n = len(buf);
	};
	for (let k = 0z; k < n; k += 1) {
		buf[k] = hist[i][k];
	};
	return n;
};

// Reads a line. The arrow keys walk the history and move along the line.
fn read_line(buf: []u8) size = {
	let n = 0z;
	let lpos = 0z;
	hist_pos = hist_count;
	for (true) {
		const c = rt::readchr();
		if (c == 0) {
			rt::cop();
			continue;
		};
		if (c == 0x1B) {
			// An escape sequence: the arrow keys and the like.
			const c1 = wait_byte();
			if (c1 != ('[': u8)) {
				continue;
			};
			const c2 = wait_byte();
			if (c2 == ('A': u8)) {
				// Up: the command before this one.
				if (hist_count > 0 && hist_pos > 0) {
					hist_pos -= 1;
					n = hist_copy(buf, hist_pos);
					lpos = n;
					repaint(buf, n, lpos);
				};
			} else if (c2 == ('B': u8)) {
				// Down: the command after this one.
				if (hist_count > 0 && hist_pos + 1 < hist_count) {
					hist_pos += 1;
					n = hist_copy(buf, hist_pos);
				} else {
					hist_pos = hist_count;
					n = 0;
				};
				lpos = n;
				repaint(buf, n, lpos);
			} else if (c2 == ('C': u8)) {
				// Right.
				if (lpos < n) {
					lpos += 1;
					out("\x1b[C");
				};
			} else if (c2 == ('D': u8)) {
				// Left.
				if (lpos > 0) {
					lpos -= 1;
					out("\x1b[D");
				};
			};
			continue;
		};
		if (c == ('\n': u8) || c == ('\r': u8)) {
			rt::println("");
			return n;
		};
		if (c == 8 || c == 127) {
			// Backspace.
			if (lpos > 0) {
				const at_end = lpos == n;
				for (let i = lpos; i < n; i += 1) {
					buf[i - 1] = buf[i];
				};
				n -= 1;
				lpos -= 1;
				if (at_end) {
					out("\b \b");
				} else {
					repaint(buf, n, lpos);
				};
			};
			continue;
		};
		if (c >= (' ': u8) && c < 0x7F) {
			if (n + 1 < len(buf)) {
				const at_end = lpos == n;
				for (let i = n; i > lpos; i -= 1) {
					buf[i] = buf[i - 1];
				};
				buf[lpos] = c;
				n += 1;
				lpos += 1;
				if (at_end) {
					rt::putc(c);
				} else {
					repaint(buf, n, lpos);
				};
			};
		};
	};
};

// Waits for the next byte of an escape sequence. A lone escape is left
// behind, so the wait does not go on forever.
fn wait_byte() u8 = {
	for (let i = 0; i < 100; i += 1) {
		const c = rt::readchr();
		if (c != 0) {
			return c;
		};
		rt::cop();
	};
	return 0;
};

// Draws the line again, with the cursor where it belongs.
fn repaint(buf: []u8, n: size, lpos: size) void = {
	// Back to the start of the line, clear it, and print it again.
	for (let i = 0z; i < lpos; i += 1) {
		out("\x1b[D");
	};
	out("\x1b[K");
	rt::write(buf[..n]);
	for (let i = lpos; i < n; i += 1) {
		out("\x1b[D");
	};
};

// A string held in a fixed array, with the end marked by a zero.
fn namestr(b: []u8) str = {
	return *(&b[..namelen(b)]: *str);
};

fn namelen(b: []u8) size = {
	let n = 0z;
	for (n < len(b) && b[n] != 0) {
		n += 1;
	};
	return n;
};

// Copies a string into a fixed array, leaving room for the zero at the end.
fn copy_str(dst: []u8, src: []u8) void = {
	let n = 0z;
	for (let i = 0z; i < len(src) && n + 1 < len(dst); i += 1) {
		dst[n] = src[i];
		n += 1;
	};
	for (let i = n; i < len(dst); i += 1) {
		dst[i] = 0;
	};
};

// Where a character is in a string, or nowhere.
fn find_char(b: []u8, c: u8) size = {
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == c) {
			return i;
		};
	};
	return NOFOUND;
};

// Makes a directory and any parent of it that is missing.
fn mkdir_p(path: []u8) bool = {
	const p = *(&path: *[]u8);
	let n = 0z;
	let i = 0z;
	if (len(p) > 0 && p[0] == ('/': u8)) {
		mktmp[0] = ('/': u8);
		n = 1;
		i = 1;
	};
	for (true) {
		let j = i;
		for (j < len(p) && p[j] != ('/': u8)) {
			j += 1;
		};
		if (j > i) {
			// The part is added to the path being made.
			if (n > 0 && mktmp[n - 1] != ('/': u8) && n + 1 < len(mktmp)) {
				mktmp[n] = ('/': u8);
				n += 1;
			};
			for (let k = i; k < j && n + 1 < len(mktmp); k += 1) {
				mktmp[n] = p[k];
				n += 1;
			};
			// A part that is already there is not a failure.
			if (!rt::exists(*(&mktmp[..n]: *str))) {
				if (!rt::mkdir(*(&mktmp[..n]: *str))) {
					return false;
				};
			};
		};
		if (j >= len(p)) {
			break;
		};
		i = j + 1;
	};
	return true;
};

let mktmp: [512]u8 = [0...];

// Removes a path and everything under it.
fn remove_tree(path: []u8, depth: size) bool = {
	if (depth >= MAXDEPTH) {
		return false;
	};
	if (!rt::isdir(*(&path: *str))) {
		return rt::remove(*(&path: *str));
	};
	let buf: [1024]u8 = [0...];
	const n = rt::readdir(*(&path: *str), buf[..]);
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				const name = buf[start..i];
				const full = join_path(treepaths[depth % 2], path, name);
				if (!remove_tree(full, depth + 1)) {
					return false;
				};
			};
			start = i + 1;
		};
	};
	return rt::remove(*(&path: *str));
};

// A path made of a directory and a name in it, written into the given buffer.
fn join_path(buf: []u8, dir: []u8, name: []u8) []u8 = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n + 1 < len(buf); i += 1) {
		buf[n] = dir[i];
		n += 1;
	};
	if (n > 0 && buf[n - 1] != ('/': u8) && n + 1 < len(buf)) {
		buf[n] = ('/': u8);
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < len(buf); i += 1) {
		buf[n] = name[i];
		n += 1;
	};
	return buf[..n];
};
