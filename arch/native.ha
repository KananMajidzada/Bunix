// Privileged port and interrupt primitives. The bodies live in native.s.

export fn outb(port: u16, val: u8) void;
export fn inb(port: u16) u8;
export fn outw(port: u16, val: u16) void;
export fn inw(port: u16) u16;
export fn cli() void;
export fn sti() void;
export fn io_wait() void;
export fn probe(addr: uintptr) u8;
export fn pause() void;
export fn ltr(sel: u16) void;
