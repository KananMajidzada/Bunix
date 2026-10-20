#!/usr/bin/env python3
"""Build a Bunix disk image from the bootloader and the kernel.

The image is laid out as:

    sector 0            the boot sector, 512 bytes, ending in 0xAA55
    sectors 1..N-1      the rest of the bootloader
    sector N onwards    the kernel, as a flat binary

The BIOS loads only sector 0 and hands it control, so the boot sector's
first job is to read the rest of itself and jump there. That second part
reads the kernel to 0x100000 on its own -- a BIOS call cannot reach above
1 MiB, and the kernel is linked there -- and then enters it.

Three numbers in boot.s are known only here, after the link: how many
sectors the loader takes, how many the kernel takes, and where the kernel
starts. They are written into the three words boot.s reserves for them,
found by symbol name, so nothing depends on a fixed offset.

    tools/mkdisk.py build/boot.elf bunix.bin bunix.img
"""
import struct
import subprocess
import sys

SECTOR = 512
BOOT_BASE = 0x7C00		# the bootloader's link address
MULTIBOOT_MAGIC = 0x1BADB002


def entry_address(payload):
    """The address the kernel asks to be entered at, from its own header.

    The kernel already states this in the Multiboot header it carries, and
    that statement is the one GRUB would honour, so it is read from there
    rather than assumed to be the load address. Those two are the same in
    many kernels and different in this one, and taking the wrong one lands
    execution inside the header itself.
    """
    if len(payload) < 32:
        raise SystemExit("mkdisk: the kernel is too short to carry a header")
    magic, flags, checksum, header_addr, load_addr, load_end, bss_end, entry = \
        struct.unpack("<8I", payload[:32])
    if magic != MULTIBOOT_MAGIC:
        raise SystemExit("mkdisk: the kernel has no Multiboot header")
    if (magic + flags + checksum) & 0xFFFFFFFF:
        raise SystemExit("mkdisk: the kernel's Multiboot checksum is wrong")
    if not flags & (1 << 16):
        raise SystemExit("mkdisk: the kernel's header does not use the "
                         "a.out kludge, so it does not say where to enter")
    return entry


def symbol(elf, name):
    out = subprocess.check_output(["nm", elf], text=True)
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    raise SystemExit(f"mkdisk: {name} not found in {elf}")


def main(argv):
    if len(argv) != 5:
        raise SystemExit("usage: mkdisk.py <boot.elf> <boot.bin> "
                         "<kernel.bin> <out.img>")
    boot_elf, boot_bin, kernel_bin, image = argv[1:5]

    payload = open(kernel_bin, "rb").read()
    boot = open(boot_bin, "rb").read()

    # The loader is the boot sector plus the sectors after it. Its length is
    # taken from the file, rounded up, because adding code must not mean
    # editing a constant that is only correct until somebody adds code.
    loader_sectors = (len(boot) + SECTOR - 1) // SECTOR
    payload_sectors = (len(payload) + SECTOR - 1) // SECTOR

    # `nm` gives the address each patched word is at, in the bootloader's
    # own address space, which starts at 0x7C00. The flat image starts at
    # that address, so subtracting it gives the offset to write at.
    patched = bytes(boot)
    for name, value in (("loader_sectors", loader_sectors),
                        ("payload_sectors", payload_sectors),
                        ("kernel_far", entry_address(payload))):
        at = symbol(boot_elf, name) - BOOT_BASE
        if at < 0 or at + 4 > len(patched):
            raise SystemExit(f"mkdisk: {name} is outside the loader")
        patched = patched[:at] + struct.pack("<I", value) + patched[at + 4:]

    # The signature has to be the last thing the BIOS sees in sector 0. If
    # the linker put it somewhere else the image is not bootable, and it is
    # better to hear about that here than from a machine that will not start.
    if patched[SECTOR - 2:SECTOR] != b"\x55\xaa":
        raise SystemExit("mkdisk: the boot sector does not end in its signature")
    if loader_sectors < 1:
        raise SystemExit("mkdisk: the loader is empty")

    with open(image, "wb") as f:
        f.write(patched)
        f.write(b"\0" * (loader_sectors * SECTOR - len(patched)))
        f.write(payload)
        f.write(b"\0" * (payload_sectors * SECTOR - len(payload)))

    print(f"mkdisk: {image}: {loader_sectors} loader sectors, "
          f"{payload_sectors} kernel sectors, "
          f"{(loader_sectors + payload_sectors) * SECTOR} bytes")


if __name__ == "__main__":
    main(sys.argv)
