/* C program entry point. The loader leaves the argument buffer in %rdi and
   its length in %rsi. __libc_start turns them into argc/argv and calls main. */
.section .entry, "ax"
.code64
.global _start
_start:
	/* No frame above us, so there is no return address to skip. */
	xorq %rbp, %rbp
	andq $-16, %rsp
	call __libc_start
1:	jmp 1b