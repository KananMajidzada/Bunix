# Bunix build configuration.

HARE = hare
HAREC = harec
QBE = qbe
AS = as
LD = ld
OBJCOPY = objcopy
AR = ar

# Host C compiler. Used to build the freestanding C runtime that cross-compiled
# Bunix programs link against, and by bcc to do the actual compiling.
CC = cc

# Target architecture. Only x86_64 is implemented.
ARCH = x86_64

QEMU = qemu-system-x86_64
