use lib;
use rt;

// Puts Bunix on a disk, so that a machine can be started from it.
//
// The kernel is read out of /dev/kernel, which is the kernel itself, and
// the boot sector is the one the kernel carries. The disk is given a
// partition table, with the kernel in the first partition and the
// filesystem in the second.

def SECT: u64 = 512;
def KERNLBA: u64 = 2048;
def ALIGN: u64 = 2048;

// Where the record in the boot sector is, and where the partition table
// and the signature go.
def RECOFF: size = 0x180;
def PTTOFF: size = 0x1BE;

const DISK: str = "/dev/disk";
const KERNEL: str = "/dev/kernel";
const BOOTSEC: str = "/dev/bootsec";
const STAGE2: str = "/dev/stage2";

// The record the kernel writes about the disk, which says how big the disk
// is and where the filesystem on it is.
let drec: [256]u8 = [0...];
let drecn: size = 0;

export @symbol("main") fn main() void = {
	rt::println("Bunix installer.");
	rt::println("");

	read_disk();
	const nsect = disk_sectors();
	if (nsect == 0) {
		rt::println("There is no disk attached.");
		return;
	};
	rt::print("The disk has ");
	rt::printnum(nsect);
	rt::println(" sectors of 512 bytes.");

	const ksize = kernel_size();
	if (ksize == 0) {
		rt::println("The kernel cannot be read.");
		return;
	};
	const ksect = (ksize + (SECT - 1)) / SECT;
	rt::print("The kernel is ");
	rt::printnum(ksize);
	rt::print(" bytes, which is ");
	rt::printnum(ksect);
	rt::println(" sectors.");

	// The filesystem stays where the kernel has already put it. Moving it
	// would mean copying every file on the disk, and there is nothing to
	// gain from it: the kernel is written before the filesystem begins.
	const dstart = disk_filesystem();
	if (dstart == 0) {
		rt::println("The filesystem cannot be found on the disk.");
		return;
	};
	if (KERNLBA + ksect > dstart) {
		rt::println("The kernel is too big for the room before the");
		rt::println("filesystem. The disk cannot hold Bunix.");
		return;
	};
	if (dstart >= nsect) {
		rt::println("The disk is too small to hold Bunix.");
		return;
	};

	rt::println("");
	rt::println("The disk will be made like this:");
	rt::print("  the kernel, at sector ");
	rt::printnum(KERNLBA);
	rt::println("");
	rt::print("  the filesystem, at sector ");
	rt::printnum(dstart);
	rt::println("");
	rt::println("");
	rt::print("Write to the disk? (yes/no) ");
	const answer = ask();
	if (!yes(answer)) {
		rt::println("Nothing was written.");
		return;
	};

	// The boot sector: the code the kernel carries, the record that says
	// where the kernel is, the partition table, and the signature that
	// tells the BIOS the disk can be started from.
	let sector: [512]u8 = [0...];
	const bs = rt::readfile(BOOTSEC, sector[..]);
	if (bs == 0) {
		rt::println("The boot sector cannot be read.");
		return;
	};
	put32(sector[RECOFF + 8..], KERNLBA);
	put32(sector[RECOFF + 12..], ksect);
	put32(sector[RECOFF + 16..], dstart);
	put32(sector[RECOFF + 20..], 0x1000);
	partition(sector[PTTOFF..], 0x80, KERNLBA, ksect);
	partition(sector[PTTOFF + 16..], 0x00, dstart, nsect - dstart);
	sector[510] = 0x55;
	sector[511] = 0xAA;

	rt::print("Writing the boot sector... ");
	if (rt::writeat(DISK, sector[..], 0) != 512) {
		rt::println("failed.");
		return;
	};
	rt::println("done.");

	// The second stage of the boot, which the boot sector reads.
	rt::print("Writing the second stage... ");
	let stage: [8192]u8 = [0...];
	const sn = rt::readfile(STAGE2, stage[..]);
	if (sn == 0) {
		rt::println("failed.");
		return;
	};
	if (rt::writeat(DISK, stage[..sn], 512) != sn) {
		rt::println("failed.");
		return;
	};
	rt::println("done.");

	// The kernel itself, in pieces, since it is too big for one buffer.
	rt::print("Writing the kernel... ");
	let buf: [8192]u8 = [0...];
	let off: u64 = 0;
	for (off < ksize) {
		const n = rt::readat(KERNEL, off, buf[..]);
		if (n == 0) {
			rt::println("failed.");
			return;
		};
		if (rt::writeat(DISK, buf[..n], (KERNLBA * SECT) + off) != n) {
			rt::println("failed.");
			return;
		};
		off += (n: u64);
	};
	rt::println("done.");

	rt::println("");
	rt::println("Bunix is on the disk. Take it out, put it in the machine");
	rt::println("you want, and start it from the disk.");
};

// Reads the record the kernel keeps about the disk.
fn read_disk() void = {
	drecn = rt::readfile("/proc/disk", drec[..]);
};

// How many sectors the disk has, or zero when there is none.
fn disk_sectors() u64 = {
	return number_after("sectors ");
};

// Where the filesystem on the disk begins.
fn disk_filesystem() u64 = {
	return number_after("filesystem at ");
};

// The number that follows a word in the record.
fn number_after(word: str) u64 = {
	const w = *(&word: *[]u8);
	let i = 0z;
	for (i < drecn) {
		if (i + len(w) <= drecn) {
			let same = true;
			for (let j = 0z; j < len(w); j += 1) {
				if (drec[i + j] != w[j]) {
					same = false;
					break;
				};
			};
			if (same) {
				i += len(w);
				break;
			};
		};
		i += 1;
	};
	let v: u64 = 0;
	let any = false;
	for (i < drecn && drec[i] >= ('0': u8) && drec[i] <= ('9': u8)) {
		v = v * 10 + ((drec[i] - ('0': u8)): u64);
		i += 1;
		any = true;
	};
	if (!any) {
		return 0;
	};
	return v;
};

// How big the kernel is, in bytes.
fn kernel_size() u64 = {
	let buf: [4096]u8 = [0...];
	let off: u64 = 0;
	for (off < 0x1000000) {
		const n = rt::readat(KERNEL, off, buf[..]);
		if (n < len(buf)) {
			return off + (n: u64);
		};
		off += (n: u64);
	};
	return 0;
};

// One entry of the partition table. The BIOS does not need the cylinder
// and head numbers, since it is told where the partitions are in sectors,
// but it is given the ones that mean "past the end" so that it does not
// try to work them out.
fn partition(entry: []u8, status: u8, lba: u64, count: u64) void = {
	entry[0] = status;
	entry[1] = 0xFE;
	entry[2] = 0xFF;
	entry[3] = 0xFF;
	entry[4] = 0x83;
	entry[5] = 0xFE;
	entry[6] = 0xFF;
	entry[7] = 0xFF;
	put32(entry[8..], lba);
	put32(entry[12..], count);
};

// A number written into a buffer, in little-endian order.
fn put32(buf: []u8, v: u64) void = {
	if (len(buf) < 4) {
		return;
	};
	buf[0] = (v & 0xFF): u8;
	buf[1] = ((v >> 8) & 0xFF): u8;
	buf[2] = ((v >> 16) & 0xFF): u8;
	buf[3] = ((v >> 24) & 0xFF): u8;
};

// Reads a line from the keyboard.
fn ask() str = {
	let line: [64]u8 = [0...];
	let n = 0z;
	for (true) {
		const c = rt::getchar();
		if (c == ('\n': u8) || c == ('\r': u8)) {
			break;
		};
		if (c == 8 || c == 127) {
			if (n > 0) {
				n -= 1;
				rt::print("\b \b");
			};
			continue;
		};
		if (n + 1 < len(line) && c >= (' ': u8) && c < 0x7F) {
			line[n] = c;
			n += 1;
			rt::putc(c);
		};
	};
	rt::println("");
	return *(&line[..n]: *str);
};

// Whether an answer says yes.
fn yes(s: str) bool = {
	if (len(s) == 0) {
		return false;
	};
	const b = *(&s: *[]u8);
	const c = b[0];
	return c == ('y': u8) || c == ('Y': u8);
};
