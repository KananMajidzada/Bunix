use lib;
use rt;

// man name...
//
// What one command is for and how it is written. help lists every name there
// is and says nothing about any of them, tutorial explains the system as a
// whole, and this is the page in between: one command at a time.
//
// The pages are kept here rather than in files on disk because a usage line
// is a thing to be looked up, and a table here cannot go out of step with the
// programs that answer for themselves. A name this has no page for but which
// is a program in /bin still gets an answer, because that much is knowable.

def WRAP: size = 72;
def MAXPAGES: size = 96;
def NAMECAP: size = 16;
// Long enough for the longest page there is, which is a little over six
// hundred bytes. A page past this is cut off and says so rather than being
// quietly shortened into a sentence that reads like a mistake.
def MAXTEXT: size = 1024;

let pagename: [MAXPAGES][NAMECAP]u8 = [[0...]...];
let pagetext: [MAXPAGES][MAXTEXT]u8 = [[0...]...];
let pagelen: [MAXPAGES]size = [0...];
let npages: size = 0;

fn namelen(i: size) size = {
	let n = 0z;
	for (let k = 0z; k < NAMECAP && pagename[i][k] != 0; k += 1) {
		n += 1;
	};
	return n;
};

fn name_of(i: size) []u8 = {
	return pagename[i][..namelen(i)];
};

// One page into the table. The first mention of a name wins, so a command
// listed twice takes the first description rather than the last.
fn page(name: []u8, text: []u8) void = {
	for (let i = 0z; i < npages; i += 1) {
		if (lib::str_eq(name_of(i), name)) {
			return;
		};
	};
	if (npages >= MAXPAGES) {
		return;
	};
	const i = npages;
	const k = if (len(name) < NAMECAP - 1) len(name) else NAMECAP - 1;
	for (let j = 0z; j < k; j += 1) {
		pagename[i][j] = name[j];
	};
	pagename[i][k] = 0;
	// A page that does not fit is cut off mid-word, which reads as a typo
	// rather than as a limit, so it ends with a mark instead.
	const t = lib::rtrim(text);
	let m = len(t);
	let cut = false;
	if (m > MAXTEXT - 8) {
		m = MAXTEXT - 8;
		cut = true;
	};
	for (let j = 0z; j < m; j += 1) {
		pagetext[i][j] = t[j];
	};
	if (cut) {
		const mark: [8]u8 = [' ', '.', '.', '.', ' ', 'c', 'u', 't'];
		for (let j = 0z; j < 8; j += 1) {
			pagetext[i][m + j] = mark[j];
		};
		m += 8;
	};
	pagelen[i] = m;
	npages += 1;
};

// A blank, for the purpose of laying out a page. lib::is_space is about
// separating the words of a command line rather than of a paragraph and
// stops short of the newline, which is the one blank this actually needs.
fn blank(c: u8) bool = {
	return c == (' ': u8) || c == ('\t': u8)
		|| c == ('\n': u8) || c == ('\r': u8);
};

// A page of text, wrapped to the width of the console. The source is written
// as flowing prose and its own line ends are only there to keep the lines of
// the file readable, so they are ignored: a blank line is what starts a new
// paragraph, and everything else is re-wrapped to the screen on the way out.
fn tell(i: size) void = {
	const text = pagetext[i][..pagelen[i]];
	let col = 0z;
	let pos = 0z;
	for (let step = 0z; pos < len(text); step += 1) {
		let ends = 0z;
		for (let j = 0z; pos < len(text) && blank(text[pos]); j += 1) {
			if (text[pos] == ('\n': u8)) {
				ends += 1;
			};
			pos += 1;
		};
		if (col > 0 && ends > 1) {
			// Two line ends together are the writer's paragraph break, and a
			// paragraph break is a blank line of screen between them.
			rt::println("");
			rt::println("");
			col = 0;
		};
		if (pos >= len(text)) {
			break;
		};
		const start = pos;
		for (let j = 0z; pos < len(text) && !blank(text[pos]); j += 1) {
			pos += 1;
		};
		const word = text[start..pos];
		if (col > 0 && col + 1 + len(word) > WRAP) {
			rt::println("");
			col = 0;
		} else if (col > 0) {
			rt::putc(' ': u8);
			col += 1;
		};
		rt::write(word);
		col += len(word);
	};
	if (col > 0) {
		rt::println("");
	};
	rt::println("");
};

fn usage(name: []u8, text: []u8) void = {
	page(name, text);
};

// The built-ins are handled inside the shell rather than run as a process, so
// their pages have to be here too.
fn pages() void = {
	usage(*(&"cat": *[]u8), *(&"cat <path>\n\nRead a file to the screen. A directory reads as the names in it, one\nper line.": *[]u8));
	usage(*(&"ls": *[]u8), *(&"ls [-l] [path]\n\nList a directory. With -l each name is preceded by its size in bytes. A\ndirectory with nothing in it says so rather than printing nothing.": *[]u8));
	usage(*(&"echo": *[]u8), *(&"echo <text>\n\nPrint the text after it.": *[]u8));
	usage(*(&"write": *[]u8), *(&"write [-a] <path> <text>\n\nPut the text in a file. With -a the text is added to what is already there\nrather than replacing it. A matching pair of quotes around the text is\ntaken off, and a backslash n or t becomes the byte it stands for.": *[]u8));
	usage(*(&"mkdir": *[]u8), *(&"mkdir <path>\n\nMake a directory.": *[]u8));
	usage(*(&"touch": *[]u8), *(&"touch <path>\n\nMake a file with nothing in it.": *[]u8));
	usage(*(&"rm": *[]u8), *(&"rm <path>\n\nRemove a file or an empty directory.": *[]u8));
	usage(*(&"hd": *[]u8), *(&"hd <path> [offset]\n\nA hex dump of a file, from a byte offset if one is given.": *[]u8));
	usage(*(&"cc": *[]u8), *(&"cc [-o outfile] file.c ...\n\nCompile with tcc and link against the runtime in /usr/lib, so the result runs\nhere rather than on a host.": *[]u8));
	usage(*(&"user": *[]u8), *(&"user <path>\n\nRun a program in a namespace of its own. Anything it writes is private to\nit and goes when it exits.": *[]u8));
	usage(*(&"multi": *[]u8), *(&"multi\n\nRun three programs at once and wait for all of them.": *[]u8));
	usage(*(&"clear": *[]u8), *(&"clear\n\nWipe the screen.": *[]u8));
	usage(*(&"pwd": *[]u8), *(&"pwd\n\nPrint the working directory. There is no chdir behind this, so it is always\nthe root.": *[]u8));
	usage(*(&"history": *[]u8), *(&"history\n\nWhat has been typed this session, oldest first. The up and down arrows\nwalk the same list.": *[]u8));
	usage(*(&"help": *[]u8), *(&"help\n\nEvery command there is, as names. This is the page for one of them; the\ntutorial is the one for the system as a whole.": *[]u8));
	usage(*(&"tutorial": *[]u8), *(&"tutorial\n\nThe system in prose: the two shells, the filesystem, writing and compiling\na program, and what a unix has that this one does not.": *[]u8));
	usage(*(&"version": *[]u8), *(&"version\n\nWhat the system says about itself, which is /proc/version.": *[]u8));
	usage(*(&"exit": *[]u8), *(&"exit\n\nLeave the shell.": *[]u8));
	usage(*(&"true": *[]u8), *(&"true\n\nNothing, and it succeeds. It is here to be a command that does not fail, for a line that has to have something on it.": *[]u8));
	usage(*(&"false": *[]u8), *(&"false\n\nNothing, and it fails. The shell does not act on the difference yet, but a command that fails is still a command that fails.": *[]u8));
	usage(*(&"man": *[]u8), *(&"man [name...]\n\nWhat a command is for and how it is written, which is this. help lists every name there is and says nothing about any of them, and tutorial explains the system as a whole. A name with no page here but which is a program in /bin still gets an answer, and one that is not a program at all says so.\n\nWith no name, every page there is, which is how to find a command whose name has been forgotten.": *[]u8));
	usage(*(&"halt": *[]u8), *(&"halt\n\nStop the machine. The shell says so first and the serial line is given a moment to drain; after that nothing runs and nothing is saved.": *[]u8));

	usage(*(&"head": *[]u8), *(&"head [-n lines] [file...]\n\nThe first lines of a file, ten unless the count says otherwise. -n, -n5 and\na bare -5 all name it.": *[]u8));
	usage(*(&"tail": *[]u8), *(&"tail [-n lines] [file...]\n\nThe last lines of a file, ten unless the count says otherwise. There is no way to follow a file as it grows: nothing here writes to a file that another process has open, so there would be nothing to follow.": *[]u8));
	usage(*(&"sort": *[]u8), *(&"sort [-n] [-r] [file...]\n\nThe lines of a file in order. -n orders by the number a line starts with,\n-r turns the result around, and lines that compare equal keep the order they\nwere in.": *[]u8));
	usage(*(&"uniq": *[]u8), *(&"uniq [-c] [-d] [file...]\n\nDrop the lines that repeat the one before. -c counts the runs and -d keeps\nonly what repeats, so a sorted file put through this says what occurs and\nhow often.": *[]u8));
	usage(*(&"cut": *[]u8), *(&"cut -d delim -f list [file...]\n\nChosen fields of each line. The list is a number, a run like 2-5, or both\nseparated by commas. The delimiter is one byte and defaults to a tab.": *[]u8));
	usage(*(&"tr": *[]u8), *(&"tr [-d] [-s] set1 [set2]\n\nReplace, delete or squeeze characters. A run in a set, as in a-z, stands\nfor every byte between its ends, which is what makes tr a-z A-Z do what it\nlooks like it does. -d deletes instead and -s folds runs down to one.": *[]u8));
	usage(*(&"nl": *[]u8), *(&"nl [-w width] [file...]\n\nNumber the lines, starting at one. -w is how wide the number is padded out to, six by default, which is what keeps the text in a column when there are more than nine lines.": *[]u8));
	usage(*(&"tac": *[]u8), *(&"tac [file...]\n\nThe lines of a file in the opposite order, which is the way to read a log. The whole file is held in memory to do it: there is no reading backwards a line at a time.": *[]u8));
	usage(*(&"rev": *[]u8), *(&"rev [file...]\n\nEach line back to front, leaving the lines in the order they were. The newline that ended a line is put back on the other end rather than reversed into the middle of it.": *[]u8));
	usage(*(&"strings": *[]u8), *(&"strings [-n min] [file...]\n\nThe runs of printable bytes in a file, which is how a binary gets searched\nwithout an editor. -n is how short a run may be.": *[]u8));
	usage(*(&"grep": *[]u8), *(&"grep <pattern> <path>\n\nThe lines holding a pattern, each printed whole and in the order they were in. The pattern is a substring and not an expression: there are no brackets, no anchors and no stars, and a pattern with one of those in it looks for that byte. A line too long to hold is searched in pieces, so a pattern spanning the join is not found.": *[]u8));
	usage(*(&"wc": *[]u8), *(&"wc <path>\n\nLines, words and bytes of a file, in that order. A word here is a run of bytes between blanks, and the newline that ends a line is counted as one of its bytes.": *[]u8));
	usage(*(&"tee": *[]u8), *(&"tee [-a] file...\n\nWrite what is typed to files as well as to the screen; Ctrl-D ends it.\nThere are no pipes here, so this is the other half of that: keeping a copy\nof something you have just watched go past.": *[]u8));
	usage(*(&"seq": *[]u8), *(&"seq [first [incr]] last\n\nA run of numbers, counting from one if only the last is given.": *[]u8));
	usage(*(&"fold": *[]u8), *(&"fold [-w width] [file]\n\nBreak long lines into shorter ones, at a space where there is one.": *[]u8));
	usage(*(&"diff": *[]u8), *(&"diff <file> <file>\n\nWhere two files part company. Lines both have are unmarked, ones only the\nfirst has are marked with a dash, and ones only the second has with a star.": *[]u8));
	usage(*(&"comm": *[]u8), *(&"comm [-123] <file> <file>\n\nThe lines two sorted files have between them, in three columns: the\nlines only the first file has, the lines only the second has, and the\nlines they share, in the order the lines sort rather than grouped by\ncolumn. A line is put where it belongs by the tabs in front of it, so\n-1 drops the first column, -2 the second, -3 the third, and what is left\ncloses up to the left behind them.\n\nBoth files have to be sorted, because that is the only thing that lets\nit work in one pass over each: the first line they both have is the same\nline, so once they part company there is nothing to look back at.": *[]u8));
	usage(*(&"paste": *[]u8), *(&"paste [-d sep] file...\n\nCorresponding lines of several files put side by side.": *[]u8));
	usage(*(&"split": *[]u8), *(&"split [-l lines] <file> <prefix>\n\nBreak a file into pieces, tagaa, tagab and on from the prefix given, -l lines each and a thousand by default. Two letters rather than one because a thousand pieces fit on a disk and a hundred do not fit on a screen.": *[]u8));
	usage(*(&"column": *[]u8), *(&"column [file]\n\nPut lines into columns, which is how a long listing stops needing\nscrolling. A column is as wide as the longest entry in it, so the longer\nthe entries the fewer of them fit across, and two blanks separate them.\nThere are no pipes, so the list has to be in a file first: ls /bin >\n/tmp/names, then column /tmp/names.": *[]u8));

	usage(*(&"mv": *[]u8), *(&"mv <src> <dst>\n\nMove a file. There is no rename of its own, so this reads, writes and then\nremoves, and the original only goes once the new file is whole. A destination\nthat is a directory takes the file inside it.": *[]u8));
	usage(*(&"cp": *[]u8), *(&"cp <src> <dst>\n\nCopy a file. It goes through the POSIX routines a block at a time rather than reading the whole thing in, so the size of the file is not the size of the memory needed to copy it.": *[]u8));
	usage(*(&"stat": *[]u8), *(&"stat <path...>\n\nWhat each path is, and for a file how many bytes it holds.": *[]u8));
	usage(*(&"tree": *[]u8), *(&"tree [path]\n\nA directory and everything under it, with the shape of the tree in the\nnames.": *[]u8));
	usage(*(&"find": *[]u8), *(&"find [path] -name pattern\n\nEvery name under a path that matches. The pattern may hold * and ?.": *[]u8));
	usage(*(&"du": *[]u8), *(&"du [path]\n\nHow much a tree holds, one line for each thing under it and then the\ntotal.": *[]u8));
	usage(*(&"cmp": *[]u8), *(&"cmp <file> <file>\n\nWhether two files hold the same bytes, and where they first part company\nif they do not.": *[]u8));
	usage(*(&"basename": *[]u8), *(&"basename <path> [suffix]\n\nThe last element of a path, with a trailing suffix taken off when one is\nnamed.": *[]u8));
	usage(*(&"dirname": *[]u8), *(&"dirname <path>\n\nEverything before the last slash in a path, and a dot when there is no slash at all rather than nothing.": *[]u8));
	usage(*(&"which": *[]u8), *(&"which <name>...\n\nWhether each name is a program the shell can run, and where it would find\nit.": *[]u8));
	usage(*(&"truncate": *[]u8), *(&"truncate [-s] <path> <bytes>\n\nCut a file down to a length. What was past that point is gone and cannot be got back. With -s a length longer than the file makes it longer instead, filling the new space with zeroes, since a hole is not something this filesystem can write.": *[]u8));
	usage(*(&"df": *[]u8), *(&"df\n\nHow much room the disk has and how much of it is taken.": *[]u8));

	usage(*(&"uname": *[]u8), *(&"uname [-a]\n\nThe system's name, or with -a the whole version file.": *[]u8));
	usage(*(&"ps": *[]u8), *(&"ps\n\nWhat is running. The kernel keeps one table of threads rather than a table\nof processes, so this can say how many are live and which slot this program\nis in, and no more.": *[]u8));
	usage(*(&"free": *[]u8), *(&"free\n\nHow much memory is free and how much there was to begin with.": *[]u8));
	usage(*(&"nproc": *[]u8), *(&"nproc\n\nHow many threads the kernel is running.": *[]u8));
	usage(*(&"uptime": *[]u8), *(&"uptime\n\nHow long the kernel has been running, in words, from the same count /proc/uptime gives in seconds. This is the kernel timer and not the clock on the motherboard: it counts from boot and never goes backwards.": *[]u8));
	usage(*(&"date": *[]u8), *(&"date [+%format]\n\nThe date and time, read from the clock on the motherboard. With a format,\n%Y the year, %m the month, %d the day, %H the hour, %M the minute, %S the\nsecond, %a the day of the week, %b the month, %s seconds since 1970, and\n%F and %T for the usual pairs.": *[]u8));
	usage(*(&"sleep": *[]u8), *(&"sleep <seconds>\n\nWait. The clock is whole seconds and nothing finer.": *[]u8));
	usage(*(&"reboot": *[]u8), *(&"reboot\n\nStart the machine again.": *[]u8));

	usage(*(&"expr": *[]u8), *(&"expr operand...\n\nWhole-number arithmetic with +, -, *, / and %, and parentheses.": *[]u8));
	usage(*(&"printf": *[]u8), *(&"printf \"<format>\" [argument]...\n\nPrint a format with the arguments filled in. %s takes a string, %d a whole\nnumber, %x the same in hex, %c one character, and zeros before the letter\npad the number out.": *[]u8));
	usage(*(&"od": *[]u8), *(&"od [-c] [-o] [-x] [file [offset]]\n\nA dump of bytes, as characters, as octal, or as hex. With no file it reads\nthe keyboard.": *[]u8));
	usage(*(&"crc32": *[]u8), *(&"crc32 [file...]\n\nThe CRC-32 of a file, its length and its name. This is the one zip and gzip\nuse, so it agrees with cksum -a crc32b on a host.": *[]u8));
	usage(*(&"md5sum": *[]u8), *(&"md5sum <file>...\n\nThe MD5 of each file. Not a cipher: it is here to name a file by what is\nin it.": *[]u8));
	usage(*(&"sha256sum": *[]u8), *(&"sha256sum <file>...\n\nThe SHA-256 of each file. The one of the family to reach for when a sum\nhas to mean something.": *[]u8));
	usage(*(&"base64": *[]u8), *(&"base64 [-d] [file]\n\nBase64, and with -d the other way round. With no file it reads the\nkeyboard.": *[]u8));
	usage(*(&"nm": *[]u8), *(&"nm [path] [symbol...]\n\nThe symbol table of an ELF file. The loader looks for _start and\n__image_end in every executable it runs, and this is how to see that they\nare there.": *[]u8));
	usage(*(&"readelf": *[]u8), *(&"readelf [path]\n\nThe parts of an ELF header worth reading: the header itself, the program\nheaders, and the section table.": *[]u8));
	usage(*(&"hello": *[]u8), *(&"hello\n\nThe smallest program with an image of its own. It is here to show that the\nloader can run a second executable next to the shell.": *[]u8));
	usage(*(&"tcc": *[]u8), *(&"tcc ...\n\nThe C compiler itself, which cc drives. It is a program here like any\nother and can be run directly.": *[]u8));
	usage(*(&"mei": *[]u8), *(&"mei <file>\n\nA text editor that draws straight onto the console. Arrows, Home and End\nmove, Ctrl-S saves, Ctrl-X saves and leaves, and Ctrl-Q throws the changes\naway.": *[]u8));
	usage(*(&"test_c": *[]u8), *(&"test_c\n\nA program the compiler is checked against at boot.": *[]u8));
};

fn in_bin(name: []u8) bool = {
	const list = lib::listdir(bindir());
	let pos = 0z;
	for (let k = 0z; pos < len(list); k += 1) {
		let (entry, next) = lib::name_at(list, pos);
		pos = next;
		if (lib::str_eq(entry, name)) {
			return true;
		};
	};
	return false;
};

fn bindir() []u8 = {
	return *(&"/bin": *[]u8);
};

export @symbol("main") fn main() void = {
	pages();
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	if (pos >= len(args)) {
		// With no name given, every page there is, which is what makes man
		// useful for finding a command whose name has been forgotten.
		rt::println("pages:");
		for (let i = 0z; i < npages; i += 1) {
			rt::write(name_of(i));
			rt::putc(' ': u8);
		};
		rt::println("");
		rt::println("");
		rt::println("man <name> for one of them. tutorial for the system.");
		return;
	};

	let missing = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (name, next) = lib::next_arg(args, pos);
		pos = next;
		let found = false;
		for (let i = 0z; i < npages; i += 1) {
			if (lib::str_eq(name_of(i), name)) {
				tell(i);
				found = true;
				break;
			};
		};
		if (found) {
			continue;
		};
		missing += 1;
		rt::print("man: no entry for ");
		rt::println(*(&name: *str));
		// A name with no page but which is a program still gets the one
		// thing that is knowable about it.
		if (in_bin(name)) {
			rt::print("it is a program in /bin; run it with no arguments for ");
			rt::println(*(&name: *str));
			rt::println("to be told how to use it.");
		};
	};
	if (missing > 0) {
		rt::println("");
	};
};