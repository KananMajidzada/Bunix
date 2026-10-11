use arch;

// Primary IDE controller in PIO mode on the conventional ports.

def DATA: u16 = 0x1F0;
def SECT: u16 = 0x1F2;
def LBA0: u16 = 0x1F3;
def LBA1: u16 = 0x1F4;
def LBA2: u16 = 0x1F5;
def DRVS: u16 = 0x1F6;
def CMDS: u16 = 0x1F7;
def STAT: u16 = 0x1F7;

def BSY: u8 = 0x80;
def DRQ: u8 = 0x40;
def ERR: u8 = 0x01;
def LSIZE: u64 = 512;

let present: bool = false;
let nsec: u64 = 0;

@init fn init() void = {
	arch::outb(DRVS, 0xA0);
	arch::io_wait();
	if (arch::inb(CMDS) == 0xFF) {
		return;
	};
	arch::outb(CMDS, 0xEC);
	if (arch::inb(CMDS) == 0x00) {
		return;
	};
	if (!wait_bsy() || !wait_drq()) {
		return;
	};
	let id: [512]u8 = [0...];
	arch::insl(DATA, (&id[0]: uintptr), 128);
	const w60 = (id[120]: u32) | ((id[121]: u32) << 8);
	const w61 = (id[122]: u32) | ((id[123]: u32) << 8);
	nsec = (w61: u64 << 16) | (w60: u64);
	for ((arch::inb(STAT) & BSY) != 0) {
		void;
	};
	present = nsec > 0;
};

export fn present_drive() bool = present;
export fn nsect() u64 = nsec;

fn wait_bsy() bool = {
	for (let i = 0z; i < 1000000; i += 1) {
		if ((arch::inb(STAT) & BSY) == 0) {
			return true;
		};
	};
	return false;
};

fn wait_drq() bool = {
	for (let i = 0z; i < 1000000; i += 1) {
		const st = arch::inb(STAT);
		if ((st & ERR) != 0) {
			return false;
		};
		if ((st & DRQ) != 0) {
			return true;
		};
	};
	return false;
};

fn select(sec: u64, cmd: u8) bool = {
	if (!present || sec >= nsec) {
		return false;
	};
	arch::outb(DRVS, 0xE0 | ((sec >> 24) & 0x0F): u8);
	arch::io_wait();
	arch::outb(SECT, 1);
	arch::outb(LBA0, sec: u8);
	arch::outb(LBA1, (sec >> 8): u8);
	arch::outb(LBA2, (sec >> 16): u8);
	arch::outb(CMDS, cmd);
	return true;
};

export fn read(sec: u64, buf: []u8) bool = {
	if (len(buf) < LSIZE: size || !select(sec, 0x20)) {
		return false;
	};
	if (!wait_bsy() || !wait_drq()) {
		return false;
	};
	arch::insl(DATA, (&buf[0]: uintptr), 128);
	return true;
};

export fn write(sec: u64, buf: []u8) bool = {
	if (len(buf) < LSIZE: size || !select(sec, 0x30)) {
		return false;
	};
	if (!wait_bsy() || !wait_drq()) {
		return false;
	};
	arch::outsl(DATA, (&buf[0]: uintptr), 128);
	if (!wait_bsy()) {
		return false;
	};
	return (arch::inb(STAT) & ERR) == 0;
};