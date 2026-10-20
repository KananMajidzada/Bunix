.text
.global rt.reboot
rt.reboot:
	cli
	movw $0x64, %dx

	# The keyboard controller takes a command only when its input buffer is
	# empty, and says so with one bit of its status register. Writing into a
	# full buffer is dropped on the floor, and a reset that is dropped on the
	# floor is the one failure mode worth being careful about here.
1:	inb %dx, %al
	test $0x02, %al
	jnz 1b

	# 0xfe is the one command the ISA gives for this: pull the reset line.
	# There is no other way to ask, because the line belongs to the
	# controller and not to anything software can reach directly.
	movb $0xfe, %al
	outb %al, %dx

	# On a machine that takes the request this never comes back. One that
	# ignores it lands here, and there is nothing sensible to do but stop
	# rather than carry on as though it had worked.
2:	pause
	jmp 2b
