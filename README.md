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
| `arch/`     | x86_64 CPU and port primitives                  |
| `boot/`     | Multiboot information parsing                   |
| `console/`  | Serial and VGA text console                     |
| `main.ha`   | Kernel entry point                              |

## Status

Early bring-up: the kernel enters long mode, sets up a stack, and reports the
memory map. See `DESIGN.md` for where it is going.
