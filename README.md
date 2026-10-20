# Bunix

An operating system written in Hare. It comes with a C compiler and a text
editor, and both of them run inside Bunix kernel/os.

![boot](doc/boot.png)

It boots into a small window manager Kit.

![windows](doc/windows.png)

tcc is part of the system. Write some C, compile it, run it, without leaving.

![compile](doc/compile.png)

	ush> write /tmp/hello.c "#include <stdio.h>\nint main(void){printf(\"hello from Bunix\\n\");return 0;}\n"
	wrote 74 bytes
	ush> cc -o /tmp/hello /tmp/hello.c
	ush> /tmp/hello
	hello from Bunix

There is also `mei`, an editor that draws straight onto the console. Arrows,
Home, End, Ctrl-S to save, Ctrl-X to save and quit.I tryed to keep it simple as i can for now. 

![editor](doc/editor.png)

Some of what the shell knows:

![help](doc/help.png)

## The shell

The prompt you normally get is `ush>`, the userland shell. It reads a line
with the cursor in it: the arrows move about, Up and Down walk back through
what you have typed, and Tab finishes a command or a path. Ctrl-L clears the
screen, Ctrl-U empties the line, Ctrl-C abandons it and Ctrl-W takes off the
word before the cursor.

`help` lists the commands and nothing else — the built-ins first, then what is
in `/bin`. `man <name>` explains one of them, and `man` on its own lists every
page there is. `tutorial` is where the explanations of the system live: what it
is, how its filesystem is laid out, how to write and compile a program, how a
program reaches the kernel, and what a unix has that this one does not.

Text: `head` `tail` `sort` `uniq` `cut` `tr` `nl` `tac` `rev` `strings` `grep`
`wc` `tee` `seq` `fold` `diff` `comm` `paste` `split` `column`

Files: `mv` `cp` `rm` `cat` `ls -l` `stat` `tree` `find` `du` `cmp`
`basename` `dirname` `which` `touch` `mkdir` `truncate`

The system: `uname` `ps` `free` `nproc` `uptime` `date` `sleep` `df`

Numbers and bytes: `expr` `printf` `od` `crc32` `base64` `md5sum` `sha256sum`

The ELF tools: `nm` `readelf`

`tr` understands runs, so `tr a-z A-Z` does what it looks like. `sort -n`
orders by the number a line starts with and `sort -r` turns the result around;
`uniq -c` then counts the runs, which is the usual way to see what repeats in
a file. `crc32` is the CRC-32 that zip and gzip use, so it agrees with
`cksum -a crc32b` on a host, down to the decimal it prints. `md5sum` and
`sha256sum` are the same sums a host gives. `nm` and `readelf` read the same
files the loader does, which is how you see why a linked executable will or
will not run.

`date` reads the clock on the motherboard through `/proc/rtc` and takes a
format after `+`, the way a host does: `date +%Y-%m-%d`. There is no quoting,
so the format runs to the end of the line.

There is no pipe between commands, so there is nothing to chain a filter into.
Each of these reads a file or the keyboard and writes the screen. `comm`,
`paste` and `column` are there for what a pipe would otherwise be used for, and
`split` for when a file is bigger than the place it has to go.

## The kernel shell

There is a second shell, in the kernel itself, with the prompt `bunix>`. It
runs the filesystem directly and needs no userland, so it is what answers if
the userland init will not start. `help` there lists what it knows.

`halt` stops the machine and `reboot` starts it again. Both are in the userland
shell as well as the kernel one. `reboot` waits for the serial line to go quiet
before it pulls the reset line, so the last thing typed arrives rather than
being lost in the port's buffer.

## Build
Needs `hare`, `qbe`, `as` and `ld` on your PATH.

	make

That leaves you a `bunix.bin`.

## Run

	qemu-system-x86_64 -m 256 -kernel bunix.bin -serial stdio

or just `make run`. The screen you get is drawn on the framebuffer; the serial
line carries the same text.

Type `help` to see what the shell knows.
