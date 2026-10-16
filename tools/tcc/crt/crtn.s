/* crtn.s - C runtime finalization section.
 * This goes into .fini and calls the user's _fini function.
 */
.section .fini,"ax"
.global _fini
.type _fini, @function
_fini:
	pushq %rbp
	movq %rsp, %rbp
	call _fini_local
	popq %rbp
	ret
.size _fini, .-_fini