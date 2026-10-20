use architecture;

// IDE disks in PIO mode.
//
// There are four of them: two on each of two controllers, and each controller
// has a master and a slave selected by a bit in the drive register. A machine
// usually has one, which is why this used to be written as though there were
// only one, with the ports as plain constants. An installer needs at least
// two -- it reads the disk it booted from and writes another -- so the ports
// became a table and the drive number became an argument.
//
// The drives are numbered the way the ATA cables are: 0 is the primary
// master, 1 the primary slave, 2 the secondary master, 3 the secondary slave.
// That is also the number a boot loader puts in the top byte of the Multiboot
// boot-device word, so the drive the kernel starts from can be named rather
// than guessed.

export type drive = struct {
	base: u16,		// the controller's first port
	slave: bool,
	present: bool,
	nsec: u64,
};

def PRIMARY: u16 = 0x1F0;
def SECONDARY: u16 = 0x170;

def DATA: u16 = 0;		// offsets from the controller's first port
def SECT: u16 = 2;
def LBA0: u16 = 3;
def LBA1: u16 = 4;
def LBA2: u16 = 5;
def DRVS: u16 = 6;
def CMDS: u16 = 7;
def STAT: u16 = 7;

def BSY: u8 = 0x80;
def DRQ: u8 = 0x40;
def ERR: u8 = 0x01;
def LSIZE: u64 = 512;

export def NDISK: size = 4;

let drives: [4]drive = [
	drive { base = PRIMARY, slave = false, present = false, nsec = 0 },
	drive { base = PRIMARY, slave = true, present = false, nsec = 0 },
	drive { base = SECONDARY, slave = false, present = false, nsec = 0 },
	drive { base = SECONDARY, slave = true, present = false, nsec = 0 },
];

// Which drive the kernel was started from, as the boot loader numbered it.
let boot_disk: size = 0;

fn controller_present(base: u16) bool = {
	architecture::outb(base + DRVS, 0xA0);		// select master
	architecture::io_wait();
	return architecture::inb(base + CMDS) != 0xFF;
};

@init fn init() void = {
	// Only probe the primary IDE channel (drives 0 and 1).
	// The secondary channel (drives 2 and 3) is rarely present on
	// modern hardware and its ports may not be implemented in
	// emulators; probing it can hang if the ports are unmapped.
	if (controller_present(PRIMARY)) {
		probe(0);
		probe(1);
	};
};

export fn set_boot_disk(n: size) void = {
	if (n < NDISK) {
		boot_disk = n;
	};
};

export fn boot_drive() size = boot_disk;

// The first drive that is there, so a machine with the disk on the secondary
// channel is not reported as having none.
fn first_present() size = {
	for (let i = 0z; i < NDISK; i += 1) {
		if (drives[i].present) {
			return i;
		};
	};
	return 0;
};

fn probe(i: size) void = {
	const d = &drives[i];
	architecture::outb(d.base + DRVS, sel_byte(d));
	architecture::io_wait();
	if (architecture::inb(d.base + CMDS) == 0xFF) {
		return;		// no controller on this channel at all
	};
	architecture::outb(d.base + CMDS, 0xEC);	// identify
	let st = architecture::inb(d.base + CMDS);
	if (st == 0x00) {
		return;		// no drive in this position
	};
	if (!wait_bsy(d) || !wait_drq(d)) {
		return;
	};
	let id: [512]u8 = [0...];
	architecture::insl(d.base + DATA, (&id[0]: uintptr), 128);
	const w60 = (id[120]: u32) | ((id[121]: u32) << 8);
	const w61 = (id[122]: u32) | ((id[123]: u32) << 8);
	d.nsec = (w61: u64 << 16) | (w60: u64);
	d.present = d.nsec > 0;
};

fn sel_byte(d: *drive) u8 = {
	if (d.slave) {
		return 0xB0;
	};
	return 0xA0;
};

export fn present_drive() bool = {
	return drives[first_present()].present;
};

export fn nsect() u64 = {
	return drives[first_present()].nsec;
};

// Whether a given drive number is one that answered, and how big it is, so a
// program can offer a list rather than make the user guess.
export fn drive_present(i: size) bool = {
	if (i >= NDISK) {
		return false;
	};
	return drives[i].present;
};

export fn drive_sectors(i: size) u64 = {
	if (i >= NDISK) {
		return 0;
	};
	return drives[i].nsec;
};

fn wait_bsy(d: *drive) bool = {
	for (let i = 0z; i < 1000000; i += 1) {
		if ((architecture::inb(d.base + STAT) & BSY) == 0) {
			return true;
		};
	};
	return false;
};

fn wait_drq(d: *drive) bool = {
	for (let i = 0z; i < 1000000; i += 1) {
		const st = architecture::inb(d.base + STAT);
		if ((st & ERR) != 0) {
			return false;
		};
		if ((st & DRQ) != 0) {
			return true;
		};
	};
	return false;
};

fn select(i: size, sec: u64, cmd: u8) bool = {
	if (i >= NDISK) {
		return false;
	};
	const d = &drives[i];
	if (!d.present || sec >= d.nsec) {
		return false;
	};
	const head = (sec >> 24) & 0x0F;
	architecture::outb(d.base + DRVS, (sel_byte(d): u8) | (head: u8) | 0x40);
	architecture::io_wait();
	architecture::outb(d.base + SECT, 1);
	architecture::outb(d.base + LBA0, sec: u8);
	architecture::outb(d.base + LBA1, (sec >> 8): u8);
	architecture::outb(d.base + LBA2, (sec >> 16): u8);
	architecture::outb(d.base + CMDS, cmd);
	return true;
};

export fn read(sec: u64, buf: []u8) bool = {
	return read_drive(first_present(), sec, buf);
};

export fn write(sec: u64, buf: []u8) bool = {
	return write_drive(first_present(), sec, buf);
};

export fn read_drive(i: size, sec: u64, buf: []u8) bool = {
	if (len(buf) < LSIZE: size || !select(i, sec, 0x20)) {
		return false;
	};
	const d = &drives[i];
	if (!wait_bsy(d) || !wait_drq(d)) {
		return false;
	};
	architecture::insl(d.base + DATA, (&buf[0]: uintptr), 128);
	return true;
};

export fn write_drive(i: size, sec: u64, buf: []u8) bool = {
	if (len(buf) < LSIZE: size || !select(i, sec, 0x30)) {
		return false;
	};
	const d = &drives[i];
	if (!wait_bsy(d) || !wait_drq(d)) {
		return false;
	};
	architecture::outsl(d.base + DATA, (&buf[0]: uintptr), 128);
	if (!wait_bsy(d)) {
		return false;
	};
	return (architecture::inb(d.base + STAT) & ERR) == 0;
};
