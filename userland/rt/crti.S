// crti.S - the prologue fragment a program's code is bracketed with.
//
// Nothing of ours lives here: startup has no per-translation-unit work to do.
// The object is linked because a conventional command line names it, and a
// program that expects to find it in /usr/lib should find it there.
.section .init
