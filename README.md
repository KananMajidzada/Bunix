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
`unalias`, `history`, `which`, `type`, `man`, `uptime`, `free`, `sleep`,
`clear`, `true`, `false`, `pushd`, `popd`, `user`, `multi`, `version`,
`help`, `tutorial`, `halt`, `poweroff` and `exit`.

The programs with an image of their own are found through `/bin` and are run
by name: `ls`, `sort`, `uniq`, `head`, `tail`, `tr`, `rev`, `seq`, `expr`,
`basename`, `dirname`, `stat`, `du`, `df`, `test`, `find`, `tree`, `grep`,
`wc`, `cp`, `mv`, `nl`, `cut`, `paste`, `comm`, `diff`, `od`, `strings`,
`cksum`, `file`, `uname`, `id`, `split`, `ps`, `kill`, `install`, `hello`,
`cc`, `tcc`, `test_c` and `mei`.

A name with a `*` in it is looked for, so a command that takes paths can be
given a pattern:

	ush> cd /usr/include
	ush> ls std*.h
	stdalign.h
	stdarg.h
	stdbool.h
	...

The output of a command can be sent to a file, with `>` to start the file
over and with `>>` to add to what is already in it:

	ush> ls /usr/include > /tmp/list
	ush> wc -l /tmp/list
	44 /tmp/list

A word can be in quotes, so a name with a space in it stays one word:

	ush> write "/tmp/with space.txt" "a line\n"
	ush> cat "/tmp/with space.txt"
	a line

A pipe is a file. The command on the left writes to `/dev/pipe0`, and the one
on the right is given that file:

	ush> cat /tmp/list | sort
	ush> cat /tmp/list | grep -n std | head -3
	1	stdalign.h
	2	stdarg.h
	3	stdbool.h
	ush> cat /tmp/list | sort > /tmp/sorted

The two commands do not run at once — the left one finishes before the right
one starts — but the file is real, and the commands that take a path work
through it.

The filters take the small flags: `sort -n -r -u`, `grep -i -v -n -c`,
`wc -l -w -c`, `comm -1 -2 -3`, `head -5`, `tail -n 5`, `cp -r`, `tr a-z A-Z`.

## The tutorial

`tutorial` walks through the system, a page at a time. It opens on a contents
page:

	ush> tutorial
	Bunix tutorial

	Bunix is a small Unix. It starts one program, the shell, and the
	shell is where you work. The one idea to keep is that everything
	you can name is a file: a directory, the disk, the kernel, the
	memory, even a pipe.

	Read a chapter with
	  tutorial 1    where you are
	  tutorial 2    files and directories
	  tutorial 3    finding things
	  tutorial 4    files that are not files
	  tutorial 5    programs and the machine
	  tutorial all  all five

	man <command> says what one command does.

A chapter is one idea, the commands that go with it, and lines to type.
Chapter 4 is the one where the idea stops being a figure of speech:

	ush> cat /proc/mem      the memory
	ush> cat /proc/uptime   seconds since it started
	ush> hd /dev/bootsec    the boot sector, in hex

`tutorial all` prints all five in one go. Anything but a number from 1 to 5
says what it takes:

	ush> tutorial 9
	usage: tutorial [1-5|all]

## Installing on a disk

Bunix can put itself on a disk. Give the machine a disk and run `install`:

	ush> install
	Bunix installer.

	The disk has 131072 sectors of 512 bytes.
	The kernel is 1369472 bytes, which is 2675 sectors.

	The disk will be made like this:
	  the kernel, at sector 2048
	  the filesystem, at sector 6144

	Write to the disk? (yes/no) yes
	Writing the boot sector... done.
	Writing the second stage... done.
	Writing the kernel... done.

	Bunix is on the disk. Take it out, put it in the machine
	you want, and start it from the disk.

Nothing is written until the answer is yes, and answering no leaves the disk
as it was. The installer asks no questions that it does not need answered,
because everything it needs is a file: the boot sector is `/dev/bootsec`, the
second stage is `/dev/stage2`, and the kernel is `/dev/kernel`.

After that the disk boots on its own:

	qemu-system-x86_64 -m 256 -drive file=disk.img,format=raw,if=ide -boot c \
		-serial stdio

The boot sector hands the memory map to the kernel in the multiboot form, so
the kernel does not care whether it was started by a multiboot loader or by
the boot sector: it reads the same map either way.

## Build
Needs `hare`, `qbe`, `as` and `ld` on your PATH.

	make

That leaves you a `bunix.bin`.

## Run

	qemu-system-x86_64 -m 256 -kernel bunix.bin -serial stdio

or just `make run`. The screen you get is drawn on the framebuffer; the serial
line carries the same text.

Type `help` to see what the shell knows, and `tutorial` for a walk through
the system, a page at a time. `man <command>` says what one command does.

To give the machine a disk, add one to QEMU and it is mounted at `/mnt`:

	qemu-system-x86_64 -m 256 -kernel bunix.bin -serial stdio \
		-drive file=disk.img,format=raw,if=ide

The disk is a file, so a copy of it is a copy of everything on it.

## Fun

Right now Bunix have mascot calling "Bunora the Hare". 

## Lisencing 

GPL lisence

