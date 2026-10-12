OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

SECTIONS {
	. = 0x400000;

	.text : ALIGN(4096) {
		*(.entry)
		*(.text)
		*(.text.*)
	}

	.rodata : ALIGN(4096) {
		*(.rodata)
		*(.rodata.*)
	}

	.data : ALIGN(4096) {
		*(.data)
		*(.data.*)
	}

	.bss : ALIGN(4096) {
		*(.bss)
		*(.bss.*)
		*(COMMON)
	}

	__image_end = .;
}