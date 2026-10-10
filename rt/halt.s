.text
.global rt.halt
rt.halt:
	cli
1:	hlt
	jmp 1b
