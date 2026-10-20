/* Where the bootloader's parts go.
 *
 * The boot sector has to be first, because that is the one sector a BIOS
 * loads on its own, and it has to be exactly one sector long, because the
 * loader is read from the sectors after it and would otherwise overlap
 * itself. The rest follows immediately, and its length is what the build
 * script counts to know how many sectors to read.
 *
 * It is linked at 0x7C00, which is where the BIOS loads a boot sector.
 */
ENTRY(boot_start)

SECTIONS
{
	. = 0x7C00;

	.bootsect : SUBALIGN(1) {
		*(.bootsect)
		. = 510;
		SHORT(0xAA55)
	}

	.loader : SUBALIGN(1) {
		*(.loader)
	}

	/DISCARD/ : {
		*(.comment)
		*(.note*)
		*(.eh_frame*)
	}
}
