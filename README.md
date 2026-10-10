# Bunix

A native operating system written in Hare, built in the spirit of Plan 9: the
kernel exposes its own small set of system calls and a 9P file interface rather
than imitating POSIX. POSIX software is served later by a userspace port
environment, not by the kernel.

The kernel currently targets x86_64 and boots as a Multiboot image.

## Building

The tree is built entirely with the Hare toolchain; there is no C in the
kernel. It expects `hare`, `harec`, `qbe`, `as`, and `ld` on `PATH`.

	make

The result is a Multiboot ELF named `bunix`.

## Running

	qemu-system-x86_64 -m 256 -kernel bunix -serial stdio

or `make run`. The kernel writes its boot log to both the VGA text console and
COM1.

## Layout

| Path        | Contents                                        |
|-------------|-------------------------------------------------|
| `rt/`       | Freestanding Hare runtime: entry, memory ops    |
| `debug/`    | Placeholder module the build driver expects     |
| `arch/`     | x86_64 CPU, port, interrupt, PIC, timer code    |
| `boot/`     | Multiboot information parsing                   |
| `mem/`      | Physical frame allocator                        |
| `console/`  | Serial, VGA text, and keyboard                  |
| `shell/`    | Console command loop                            |
| `main.ha`   | Kernel entry point                              |

## Status

The kernel enters long mode, brings up the serial and VGA consoles, reads the
Multiboot memory map, manages physical frames with a bitmap, and runs a
PIT-driven clock behind an interrupt descriptor table. A small command loop is
available on the console:

	echo clear frames fault halt help mem uptime

![boot](doc/boot.png)

There are no processes, no filesystem, and no 9P yet. See `DESIGN.md` for where
it is going.
