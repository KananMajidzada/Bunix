.section .entry, "ax"
.code64
.global _start
_start:
	call rt.start_hare
1:	jmp 1b
