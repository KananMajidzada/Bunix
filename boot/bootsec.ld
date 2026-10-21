# The boot sector is loaded by the BIOS at 0x7C00, so that is where it is
# linked. The record the installer fills in is at a fixed place in the
# sector, so the data section is put there too.

OUTPUT_FORMAT(elf32-i386)
ENTRY(_start)

SECTIONS {
	. = 0x7C00;

	.text : {
		*(.text)
	}

	. = 0x7D80;

	.data : {
		*(.data)
	}

	. = 0x7E00;

	/DISCARD/ : {
		*(.note.gnu.property)
		*(.note.*)
	}
}
