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

# The user program is a freestanding Hare program with its own runtime under
# userland/. It links at a fixed address, so it becomes a flat blob folded into
# the kernel as a byte array the shell loads into the reserved user region.
USER_SRCS = $(shell find userland -name '*.ha' -o -name '*.s' -o -name '*.sc')

build/userprog: $(USER_SRCS)
	@mkdir -p build
	cd userland && HAREPATH=. $(HARE) build -F -a$(ARCH) -o $(CURDIR)/build/userprog

build/prog.bin: build/userprog
	$(OBJCOPY) -O binary $< $@

user/blob.ha: build/prog.bin
	@{ n=$$(wc -c < build/prog.bin); \
	   e=$$(nm build/userprog | awk '$$3 == "_start" { print $$1 }'); \
	   printf 'export const prog: [%s]u8 = [' "$$n"; \
	   od -An -tu1 -v build/prog.bin | awk '{ for (i = 1; i <= NF; i++) printf "%s,", $$i }'; \
	   printf '];\nexport const entry: u64 = 0x%s;\n' "$$e"; } > $@

run: bunix.bin
	$(QEMU) -m 256 -kernel bunix.bin -serial stdio

run-nographic: bunix.bin
	$(QEMU) -m 256 -kernel bunix.bin -display none -serial stdio

clean:
	rm -rf bunix bunix.bin build user/blob.ha

.PHONY: all run run-nographic clean
