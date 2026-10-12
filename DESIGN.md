# Design

## The shape of the system

Bunix is native first. The kernel offers its own system calls and models the
machine as a set of file servers. It is not a Unix clone and does not try to be.
Programs that expect POSIX are served by a userspace port environment that
translates POSIX calls onto the native interface.

The layering, from bottom to top:

	port/        POSIX library and shell, linked into the user program
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

Programs written against the shim run as command bodies in the user program;
`wc`, `grep`, and `cp` are the first. There is no separate binary loader yet,
so everything links into the one image the kernel knows how to start. A loader
and a C compiler driver are still to come.

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

Started: the port environment. A POSIX shim in userspace gives the user program
`open`, `read`, `write`, `close`, and `lseek` over the native whole-file calls,
and `wc`, `grep`, and `cp` are written against it.

Next: the port environment.

## Roadmap

1. Console, memory map, and a physical page allocator. [done]
2. Interrupts, a timer, and a scheduler. [done]
3. Kernel threads and a first userspace process. [done]
4. A file-server core and a per-process namespace. [done]
5. `/dev`, `/proc`, and an init process. [done]
6. The port environment: a POSIX library, a shell, and a C compiler driver.
   [shim and first programs done; loader and compiler driver next]
7. A filesystem with persistence. [done]
