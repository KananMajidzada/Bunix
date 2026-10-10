OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

SECTIONS {
	. = 0x00100000;

	.multiboot : ALIGN(4) {
		KEEP(*(.multiboot))
	}

	.boot : ALIGN(4096) {
		KEEP(*(.boot))
	}

	.text : ALIGN(4096) {
		KEEP(*(.text))
		*(.text.*)
	}

	.rodata : ALIGN(4096) {
		KEEP(*(.rodata))
		*(.rodata.*)
	}

	.data : ALIGN(4096) {
		KEEP(*(.data))
		*(.data.*)
	}

	.init_array : ALIGN(8) {
		PROVIDE_HIDDEN(__init_array_start = .);
		KEEP(*(.init_array))
		PROVIDE_HIDDEN(__init_array_end = .);
	}

	.fini_array : ALIGN(8) {
		PROVIDE_HIDDEN(__fini_array_start = .);
		KEEP(*(.fini_array))
		PROVIDE_HIDDEN(__fini_array_end = .);
	}

	.bss : ALIGN(4096) {
		KEEP(*(.bss))
		*(.bss.*)
		*(COMMON)
	}

	_kernel_end = .;
}
