.section .entry, "ax"
.code64
.global _start
_start:
	movq %rdi, rt.arg_ptr(%rip)
	movq %rsi, rt.arg_len(%rip)
	call rt.start_hare
1:	jmp 1b
