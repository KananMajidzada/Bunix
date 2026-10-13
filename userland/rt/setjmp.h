// setjmp.h - non-local jumps.
//
// tcc uses these to unwind out of a failed parse, so they have to be real: the
// callee-saved registers and the return address are parked by setjmp and put
// back by longjmp.

#ifndef BUNIX_SETJMP_H
#define BUNIX_SETJMP_H

// Eight callee-saved registers, the stack pointer and the return address,
// with room to spare. Slot 7 holds the frame pointer the caller's own frame
// sits in.
typedef unsigned long jmp_buf[25];

typedef unsigned long sigjmp_buf[25];

int setjmp(jmp_buf env);
int _setjmp(jmp_buf env);
void longjmp(jmp_buf env, int val);
void _longjmp(jmp_buf env, int val);

#define sigsetjmp(env, savemask) setjmp(env)
#define siglongjmp(env, val) longjmp(env, val)

#define setjmp setjmp

#endif
