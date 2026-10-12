// Privileged port and interrupt primitives. The bodies live in native.s.

export fn outb(port: u16, val: u8) void;
export fn inb(port: u16) u8;
export fn outw(port: u16, val: u16) void;
export fn inw(port: u16) u16;
export fn outl(port: u16, val: u32) void;
export fn inl(port: u16) u32;
export fn insl(port: u16, buf: uintptr, count: u32) void;
export fn outsl(port: u16, buf: uintptr, count: u32) void;
export fn cli() void;
export fn sti() void;
export fn io_wait() void;
export fn probe(addr: uintptr) u8;
export fn pause() void;
export fn memcpy(dst: uintptr, src: uintptr, n: size) void;
export fn store64(dst: uintptr, word: u64, count: size) void;
export fn ltr(sel: u16) void;
export fn read_cr3() uintptr;
export fn write_cr3(space: uintptr) void;
export fn invlpg(addr: uintptr) void;
