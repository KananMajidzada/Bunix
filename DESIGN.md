# Design

## The shape of the system

Bunix is native first. The kernel offers its own system calls and models the
machine as a set of file servers speaking 9P, in the tradition of Plan 9. It is
not a Unix clone and does not try to be. Programs that expect POSIX are served
by a userspace port environment that translates POSIX calls onto the native
interface, the way Plan 9's APE sat on top of 9P.

The layering, from bottom to top:

	port/         POSIX library and shell (not written yet)
	9P servers    userspace file servers: /dev, /net, /proc, ...
	namespace     per-process mount and bind tables
	kernel        boot, memory, scheduler, IPC, drivers

Everything is a file. A device, a network stack, a window system, and a
process's own address space are all reached by walking a namespace that each
process builds for itself out of mounts and binds. The kernel's job is to make
that model fast and safe, not to guess what a POSIX program wants.

## Why a single kernel

Bunix is a single kernel image, not a microkernel. Drivers and file servers can
move to userspace when there is a reason to, but the scheduling, memory, and
9P plumbing live in the kernel where they can be simple. A microkernel here
would trade a small amount of isolation for a large amount of IPC before any of
it earned its keep.

## Boot

The kernel is a Multiboot 1 image. The boot loader enters us in 32-bit
protected mode; `rt/start.s` raises the CPU into long mode with an identity map
of the first gigabyte, then calls into Hare. The runtime runs the `@init`
functions and calls `main`, which receives the physical address of the
Multiboot information structure.

There is no higher-half mapping yet. The kernel runs where it is loaded, at 1
MiB, and moves once there is a reason to.

## Conventions

The tree follows the upstream Hare style guide, with a few local habits kept
consistent everywhere:

- Tabs for indentation, one statement per line, 80 columns.
- `snake_case` for functions and variables, `UPPER_CASE` for constants.
- Comments explain why, not what; there are few of them.
- One idea per module. The kernel talks to hardware through `arch`, learns
  where it is from `boot`, and speaks to the operator through `console`.

## Roadmap

1. Console, memory map, and a physical page allocator.
2. Interrupts, a timer, and a scheduler.
3. Kernel threads and a first userspace process.
4. A 9P server core and a per-process namespace.
5. `/dev`, `/proc`, and an init process.
6. The port environment: a POSIX library, a shell, and a C compiler driver.
