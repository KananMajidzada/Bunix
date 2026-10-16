/* crti.s - C runtime initialization section.
 * This goes into .init and calls the user's _init function.
 */
.section .init,"ax"
.global _init
.type _init, @function
_init:
	pushq %rbp
	movq %rsp, %rbp
	call _init_local
	popq %rbp
	ret
.size _init, .-_init