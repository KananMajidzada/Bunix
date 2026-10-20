// Starts the machine again. The reset line belongs to the keyboard controller
// and is pulled by writing one command byte to its port, which is all the
// assembly next door does.
export fn reboot() never;