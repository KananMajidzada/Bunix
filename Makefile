.POSIX:
.SUFFIXES:

include config.mk

SRCS = $(shell find . -name '*.ha' -o -name '*.s' -o -name '*.sc')

all: bunix.bin

# The kernel is a freestanding Hare program. HAREPATH is pointed at the tree
# itself so the build only sees our runtime and modules.
bunix: user/blob.ha $(SRCS)
	HAREPATH=. $(HARE) build -F -a$(ARCH) -o $@

# QEMU's built-in Multiboot loader only accepts 32-bit ELF, so hand it a flat
# image and let rt/start.s raise the CPU into long mode itself.
bunix.bin: bunix
	$(OBJCOPY) -O binary bunix $@

# The user program is assembled and linked into a flat blob, then folded into
# the kernel as a byte array the shell can load into a fresh frame.
build/prog.o: user/prog.asm
	@mkdir -p build
	$(AS) --64 -o $@ $<

build/prog.elf: build/prog.o user/link.ld
	$(LD) -T user/link.ld -o $@ build/prog.o

build/prog.bin: build/prog.elf
	$(OBJCOPY) -O binary $< $@

user/blob.ha: build/prog.bin
	@{ n=$$(wc -c < build/prog.bin); \
	   printf 'export const prog: [%s]u8 = [' "$$n"; \
	   od -An -tu1 -v build/prog.bin | awk '{ for (i = 1; i <= NF; i++) printf "%s,", $$i }'; \
	   printf '];\n'; } > $@

run: bunix.bin
	$(QEMU) -m 256 -kernel bunix.bin -serial stdio

run-nographic: bunix.bin
	$(QEMU) -m 256 -kernel bunix.bin -display none -serial stdio

clean:
	rm -rf bunix bunix.bin build user/blob.ha

.PHONY: all run run-nographic clean
