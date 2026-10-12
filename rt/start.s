.section .multiboot, "a"
.align 4
multiboot_header:
.long 0x1BADB002				/* magic */
.long 0x00010007				/* flags: modules, memory, a.out kludge, video */
.long -(0x1BADB002 + 0x00010007)		/* checksum */
.long multiboot_header				/* header address */
.long 0x00100000				/* load address */
.long 0						/* load end: whole file */
.long _kernel_end				/* bss end */
.long _start					/* entry */
.long 0						/* mode type: graphics */
.long 1024					/* width */
.long 768					/* height */
.long 32					/* depth */

.section .boot, "ax"
.code32
.global _start
_start:
	cli
	movl $0, mb_info
	cmpl $0x2BADB002, %eax
	jne 1f
	movl %ebx, mb_info
1:
	/* Clear the three page table pages. */
	xorl %eax, %eax
	leal boot_pml4, %edi
	movl $0x0C00, %ecx
2:	movl %eax, (%edi)
	addl $4, %edi
	decl %ecx
	jnz 2b

	/* Identity map 1 GiB: 512 entries of 2 MiB, present, writable, user. */
	leal boot_pd, %edi
	xorl %ecx, %ecx
	movl $0x00000087, %eax
3:	movl %eax, (%edi)
	addl $0x200000, %eax
	addl $8, %edi
	incl %ecx
	cmpl $512, %ecx
	jb 3b

	/* Link the page directory into the PDPT and the PDPT into the PML4. */
	leal boot_pd, %eax
	orl $0x07, %eax
	movl %eax, boot_pdpt
	leal boot_pdpt, %eax
	orl $0x07, %eax
	movl %eax, boot_pml4

	/* Enable PAE and load the PML4. */
	movl %cr4, %eax
	orl $(1 << 5), %eax
	movl %eax, %cr4
	leal boot_pml4, %eax
	movl %eax, %cr3

	/* Set EFER.LME to request long mode. */
	movl $0xC0000080, %ecx
	rdmsr
	orl $(1 << 8), %eax
	wrmsr

	/* Turn on paging; the CPU enters long mode on the next far jump. */
	movl %cr0, %eax
	orl $(1 << 31), %eax
	movl %eax, %cr0

	lgdt gdt64_ptr
	ljmp $0x08, $long_entry
.code64
long_entry:
	movw $0x10, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw %ax, %fs
	movw %ax, %gs
	movq $stack_top, %rsp
	xorq %rbp, %rbp
	movl mb_info, %edi
	call rt.start_hare
4:	cli
	hlt
	jmp 4b

.section .data
.align 8
gdt64:
	.quad 0x0000000000000000			/* null */
	.quad 0x00AF9A000000FFFF			/* code, ring 0 */
	.quad 0x00CF92000000FFFF			/* data, ring 0 */
	.quad 0x00AFFA000000FFFF			/* code, ring 3 */
	.quad 0x00CFF2000000FFFF			/* data, ring 3 */
.global gdt64_tss
gdt64_tss:
	.quad 0
	.quad 0
gdt64_ptr:
	.word gdt64_ptr - gdt64 - 1
	.quad gdt64

.global tss
.align 16
tss:
	.long 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.quad 0
	.word 0
	.word 104
tss_end:

.section .bss
.align 4096
boot_pml4:
	.skip 4096
boot_pdpt:
	.skip 4096
boot_pd:
	.skip 4096
.global boot_pdpt
mb_info:
	.skip 4
.align 16
stack_bottom:
	.skip 16384
stack_top:
