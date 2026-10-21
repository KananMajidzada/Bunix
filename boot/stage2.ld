# The second stage is read to 0x8000 by the boot sector, so that is where it
# is linked.

OUTPUT_FORMAT(elf32-i386)
ENTRY(_start)

SECTIONS {
	. = 0x8000;

	.text : {
		*(.text)
	}

	.data : {
		*(.data)
	}

	. = 0x9000;
}
