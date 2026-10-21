# Bunix-Bunny's Unix

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

The shell `ush` is the one you land in. It keeps a working directory, a
history and a few aliases, and the arrow keys walk the history.

	ush> cd /usr/include
	ush> ls stdio.h
	stdio.h
	ush> pwd
	/usr/include
	ush> alias ll="ls -l"
	ush> ll /bin
	hello                       12392
	wc                          21552
	ush> history
	1  cd /usr/include
	2  ls stdio.h

The commands of the shell itself are `cat`, `cd`, `pwd`, `echo`, `write`,
`mkdir`, `touch`, `rm`, `hd`, `cc`, `env`, `export`, `unset`, `alias`,
`unalias`, `history`, `which`, `man`, `uptime`, `free`, `sleep`, `clear`,
`true`, `false`, `user`, `multi`, `version`, `help` and `exit`.

The programs with an image of their own are found through `/bin` and are run
by name: `ls`, `sort`, `uniq`, `head`, `tail`, `tr`, `rev`, `seq`, `expr`,
`basename`, `dirname`, `stat`, `du`, `df`, `test`, `find`, `tree`, `grep`,
`wc`, `cp`, `hello`, `cc`, `tcc` and `mei`.

A name with a `*` in it is looked for, so a command that takes paths can be
given a pattern:

	ush> cd /usr/include
	ush> ls std*.h
	stdalign.h
	stdarg.h
	stdbool.h
	...

## Build
Needs `hare`, `qbe`, `as` and `ld` on your PATH.

	make

That leaves you a `bunix.bin`.

## Run

	qemu-system-x86_64 -m 256 -kernel bunix.bin -serial stdio

or just `make run`. The screen you get is drawn on the framebuffer; the serial
line carries the same text.

Type `help` to see what the shell knows.

To give the machine a disk, add one to QEMU and it is mounted at `/mnt`:

	qemu-system-x86_64 -m 256 -kernel bunix.bin -serial stdio \
		-drive file=disk.img,format=raw,if=ide
