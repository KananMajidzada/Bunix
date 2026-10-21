# Design

## The shape of the system

Bunix is native first. The kernel offers its own system calls and models the
machine as a set of file servers. It is not a Unix clone and does not try to be.
Programs that expect POSIX are served by a userspace port environment that
translates POSIX calls onto the native interface.

The layering, from bottom to top:

	userland/    POSIX library, shell, and programs, built into user images
	file servers userspace servers: /dev, /net, /proc, ...
	namespace    per-process mount and bind tables
	kernel       boot, memory, scheduler, IPC, drivers

A device, a network stack, a window system, and a process's own address space
are all reached by walking a namespace that each process builds for itself out
of mounts and binds. The kernel's job is to make that model fast and safe, not
to guess what a POSIX program wants.

## The Bunix File Protocol

File servers are reached over the Bunix File Protocol (BFP), the system's own
request/reply protocol. It is deliberately small: a fixed header, a handful of
message pairs, and a per-connection handle table. Files are located by walking
from a root handle one name at a time, and each file carries an ident so two
names can be compared without a round trip.

The design borrows the general shape of earlier file protocols — typed
messages, walkable names, handles — but the message set, numbering, and naming
are ours. Nothing here is wire-compatible with another system.

## Why a single kernel

Bunix is a single kernel image, not a microkernel. Drivers and file servers can
move to userspace when there is a reason to, but the scheduling, memory, and
protocol plumbing live in the kernel where they can be simple. A microkernel
here would trade a small amount of isolation for a large amount of IPC before
any of it earned its keep.

## Boot

The kernel is a Multiboot 1 image. The boot loader enters us in 32-bit
protected mode; `rt/start.s` raises the CPU into long mode with an identity map
of the first gigabyte, then calls into Hare. The runtime runs the `@init`
functions and calls `main`, which receives the physical address of the
Multiboot information structure. One `@init` probes the primary IDE controller
through the `block` module and learns its size, when a drive is present.

There is no higher-half mapping yet. The kernel runs where it is loaded, at 1
MiB, and moves once there is a reason to.

Bunix can also start itself, from a disk it was installed onto. That path has
two stages, because one sector is not enough.

The boot sector lives in the first sector of the drive and is 512 bytes. It
has to fit in one sector and below 0x7E00 in memory, which leaves it no room
to be clever. It does two things: it asks the BIOS for the memory map, and it
reads the second stage into 0x8000. It cannot read the kernel itself: the
kernel is over a megabyte, and the BIOS read service only reaches the first
megabyte of memory.

The second stage is 8 KiB at 0x8000. It has its own driver for the ATA
controller, polling the data port a sector at a time, because the BIOS read
service cannot reach the kernel either. It loads the kernel to 1 MiB, puts the
machine into 32-bit protected mode, builds the multiboot information
structure, and jumps to the kernel. It has to switch to protected mode
first: jumping into a 64-bit kernel while the CPU is still in real mode
resets the machine, which looks exactly like a boot that does not work.

The memory map is the trick that keeps the two paths the same. The boot
sector asks the BIOS for the E820 map and writes it out in the multiboot
form, so the kernel reads the same structure whichever way it was started.
When the bootloader says nothing about the memory, the kernel takes the whole
of it above the kernel to be there to be used.

The disk layout is:

	sector 0        the boot sector, with a partition table
	sector 1        the second stage
	sector 2048     the kernel
	sector 6144     the filesystem

The boot sector keeps a record of where the kernel and the filesystem are, so
the kernel can find the filesystem on a disk it did not write itself.

## Installing

Everything the installer needs is a file: `/dev/bootsec` holds the boot
sector, `/dev/stage2` holds the second stage, and `/dev/kernel` holds the
kernel. The kernel folds the first two into itself as byte tables, so a
machine can be given the means to install itself.

The installer is text, and it asks before it writes. It says how big the disk
is, how big the kernel is, and where the two will go, and waits for a yes.
Answering no leaves the disk as it was. There is no second stage of the
install, and no separate program to copy onto a floppy: the installer is a
program like any other, and it is run from the shell.

The kernel is over a megabyte, so it cannot be held in memory and written in
one go. The `readat` and `writeat` calls move a file a piece at a time, from
an offset, and the installer uses them to copy the kernel onto the disk
without ever holding all of it.

## Storage

An ATA PIO driver in `block/` talks to the primary IDE controller on the
conventional ports, one sector at a time, polling for busy and data-ready
instead of using interrupts. The whole drive is reachable raw as `/dev/disk`:
any byte offset is translated into whole sectors, with read-modify-write for
partial ones.

A second, higher layer keeps the file tree on the drive. The tree that lives
under `/mnt` is disk-backed: a superblock in sector 0 (magic, root directory,
next free block), directory blocks that hold up to eight 42-byte entries of
type, name, data block, and length, and contiguous data blocks for file
contents. Every create, write, and remove writes straight through to the
sectors, so the same file is there on the next boot. Dirs and files created
anywhere else in the initial tree are still memory-only. The raw `/dev/disk`
node is unfenced, so writing it can scribble on the format.

QEMU backs the drive with a raw file, so a sector written today stays in the
file and is still there on the next boot.

## Graphics

The boot header asks for a linear 1024x768x32 framebuffer. When the loader
supplies one, `fb` maps it — it lives above 1 GiB — into every address space
through a single shared page-directory table, and only falls back to setting a
VBE mode itself when there is no loader framebuffer.

Drawing never touches the device directly. `fb` keeps a shadow copy of the
screen in ordinary RAM and every primitive writes there; `present` copies the
whole shadow to the framebuffer in one pass. A frame is therefore always a
complete, consistent picture, and moving or resizing a window cannot leave a
trail behind, because nothing is ever drawn over stale device pixels.

The mouse is a PS/2 device on the keyboard controller's aux port. The console's
wait loops poll it, decode three-byte packets, and hand the deltas and button
mask to the window manager; the keyboard status byte's aux bit keeps mouse
bytes out of the key stream. More than one thread can be waiting for input at
once, so packet assembly runs with interrupts held, and a guard serialises the
redraw that follows. The yield path polls as well, so the pointer keeps moving
while a spawned program runs.

`kit` is a small rio-style window manager over the frame buffer: a stack of
overlapping terminals, each with a title bar, a border, and a scrollbar. The
middle and right buttons raise a pop-up menu holding `new`, `resize`, `move`,
`delete`, `hide`, and `exit`; the left button selects text in a window, drags
the window by its title, or grabs a border once the pointer rests against it
and the frame turns black. Console output goes to whatever window has focus.
Opening a window marks it fresh, and the shell prints a prompt into it, so a new
terminal is ready to type in. Like the text console, it lives in the kernel for
now; the plan is for a window system to become one more file server a process
can mount.

## Processes and memory

Kernel threads are scheduled round-robin by the timer. Each thread carries a
stack and a saved register frame; the timer interrupt swaps frames to switch.

User processes run in ring 3. The GDT carries ring-3 code and data segments plus
a TSS that holds the kernel stack used when a trap enters the kernel. System
calls arrive on `int 0x80`, with the number in `rax` and arguments in `rdi`,
`rsi`, `rdx`, and `rcx`.

Every process has its own page tables. The kernel identity maps the first
gigabyte supervisor-only in each address space, so traps and system calls keep
working after the switch, while a private 2 MiB window at `0x400000` is mapped
user-accessible through a dedicated page table. The scheduler loads the right
page tables on each switch. User memory is handed out by mapping fresh frames
into that window. A process that touches supervisor memory or an unmapped
address is killed, and the rest of the system keeps running. When a process
exits or is killed, its page tables, every frame mapped into its window, its
kernel stack, and its private file nodes go back to their allocators.

## Namespaces

Each process also carries a file namespace: its own handle table and its own
flavor of the root directory. `init` and the kernel live on the shared root,
which holds `/dev`, `/proc`, and the files anyone creates there. A freshly
spawned process instead gets a private root with `/dev` and `/proc` bound in
and its own `/tmp`, so its files are private to it. The BFP server keeps one
handle table per namespace and starts every attach at that namespace's root.

A namespace also holds the directory its process is in. A path that starts
with a slash is looked for from the root of the namespace; a path that does
not is looked for from there, and `.` and `..` are folded away on the way.
The directory is a node in the tree rather than a name, so two processes can
be in different places at once, and a process that shares a namespace with
the one that started it starts where that one is. The `chdir` and `pwd` calls
are how a process says where it is.

## The port environment

The kernel speaks its own calls; a POSIX layer shoved into it would be the
wrong thing to put there. The shim lives in userspace instead, in
`userland/posix`, and links into the user program. It is the one place that
keeps the mismatch between POSIX and the native interface.

The native calls move whole files: `readfile` fills a buffer and `writefile`
drains one. On top of them the shim offers `open`, `read`, `write`, `close`,
and `lseek`. Opening for read slurps the file into a buffer and hands out
slices of it; opening for write collects bytes and flushes them on close.
Descriptors 0, 1, and 2 are the console, and a read from 0 waits on the
keyboard.

Programs written against the shim used to run as command bodies in the one user
image; now each has an image of its own. `userland/prog/<name>` is built and
linked at the same base as the shell, and the images are folded into the kernel
as raw bytes beside a table naming each one. When a process asks for a program,
the loader picks an image by the first word of the command line — a path is
stripped to its last element — and starts it in the caller's namespace, so it
opens the same files the caller would. If no image matches, the shell image
runs instead, so the built-ins and the single-image commands are unaffected.

A `/bin` that programs are discovered through is there now, and so is a C
compiler driver that compiles against the shim.

## The shell

The shell is the userland program the kernel starts first, and it is the way
into everything else. It keeps a working directory, a history of the commands
that have been run, and a set of aliases. The arrow keys walk the history and
move along the line, and the escape sequences the kernel's keyboard driver
already sends are what the shell reads them from.

The commands of the shell itself work on paths, so they follow the working
directory: `cat`, `write`, `mkdir`, `rm` and `hd` take a path, and `cd` moves
between them. The rest are about the machine: `pwd`, `env`, `export`, `unset`,
`alias`, `unalias`, `history`, `which`, `man`, `uptime`, `free`, `sleep`,
`clear`, `true` and `false`.

A program with an image of its own is found through `/bin` and run by name.
The loader takes the first word of the line to pick the image, so the program
is handed the rest of the line and nothing else: `sort /tmp/x` arrives at
`sort` as `/tmp/x`.

A word with a `*` in it is looked for before the line is handed over, and
the names that match take its place. Only a command that takes paths is
looked at this way, since the text of a write is not a path and a `*` in it
is just a `*`. A word that matches nothing is left as it was, so the program
can say that it cannot find it.

The output of a command can be sent to a file, with `>` to start the file
over and with `>>` to add to what is in it. The redirection is done by the
kernel rather than by the shell, because the shell is not the only thing
whose output can be redirected: a program with an image of its own writes
through the same call. The kernel keeps the file and the place in it per
thread, and a program started while the output is going to a file inherits
it, so `ls /usr > /tmp/list` puts the listing of the directory in the file,
and not just the echo of it.

There is still no pipe. A pipe wants two ends and something in the middle,
and the kernel moves whole files rather than bytes.

## Conventions

The tree follows the upstream Hare style guide, with a few local habits kept
consistent everywhere:

- Tabs for indentation, one statement per line, 80 columns.
- `snake_case` for functions and variables, `UPPER_CASE` for constants.
- Comments explain why, not what; there are few of them.
- One idea per module. The kernel talks to hardware through `arch`, learns
  where it is from `boot`, and speaks to the operator through `console`.

## Status

Done: the boot path, serial and VGA consoles, the Multiboot memory map, a
physical frame allocator, timer interrupts with an IDT, a runtime heap, kernel
threads, a first userspace process, per-process address spaces, several
processes running at once, a user-mode init with an interactive shell, an
in-memory file tree served over the Bunix File Protocol with create, read,
write, and remove, a per-process namespace that binds in the shared /dev and
/proc while giving every process private space of its own, full reclamation of
a process's memory, page tables, and files when it leaves, and an ATA PIO
driver that turns an IDE drive into a persistent raw `/dev/disk`, and a
disk filesystem mounted at `/mnt` that keeps the file tree across reboots.

Done also: a graphical console. A framebuffer, a PS/2 mouse, and a rio-style
window manager with overlapping terminals, a pop-up menu, border resize, title
drag, and hide and delete, all drawn through a RAM shadow buffer that is copied
to the device whole.

Done also: a working directory for every process, so a path that does not
start with a slash is looked for from where the process is, and `cd` and
`pwd` say so. The shell has a history the arrow keys walk, aliases, and an
environment of its own.

Done also: a boot from a real disk. A boot sector and a second stage that
put the kernel on a drive and start it, and an installer that does the
writing and asks before it writes. The kernel, the second stage and the boot
sector are files in the kernel, so the machine can install itself.

Done also: the output of a command can be sent to a file, with `>` and
`>>`, for the commands the shell has built in and for the programs that have
an image of their own.

Started: the port environment. A POSIX shim in userspace gives the user program
`open`, `read`, `write`, `close`, and `lseek` over the native whole-file calls.
`wc`, `grep`, and `cp` are written against it, and each is a loadable image of
its own.

Next: a C compiler driver for the port environment.

## Roadmap

1. Console, memory map, and a physical page allocator. [done]
2. Interrupts, a timer, and a scheduler. [done]
3. Kernel threads and a first userspace process. [done]
4. A file-server core and a per-process namespace. [done]
5. `/dev`, `/proc`, and an init process. [done]
6. The port environment: a POSIX library, a shell, and a C compiler driver.
   [shim, loader, and first programs done; compiler driver next]
7. A filesystem with persistence. [done]
8. A working directory for every process, and a shell that follows it.
   [done]
9. A boot from a disk: a boot sector, a second stage, and an installer.
   [done]
10. Output redirection. [done]
