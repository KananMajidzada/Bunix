// initfini.c - provide _init_local and _fini_local for CRT compatibility

void _init_local(int argc, char **argv, char **envp, void (*cleanup)(void)) {
    // No-op for Bunix - no constructor handling needed
    (void)argc; (void)argv; (void)envp; (void)cleanup;
}

void _fini_local(void) {
    // No-op for Bunix - no destructor handling needed
}
