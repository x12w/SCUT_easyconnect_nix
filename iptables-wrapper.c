/* Custom SUID wrapper for iptables.
   The NixOS security.wrappers SUID wrapper sets euid=0 but not real uid.
   iptables refuses to run when getuid() != geteuid().
   This wrapper sets BOTH real and effective uid to 0,
   then exec's the real iptables binary. */
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

extern char **environ;

/* The real iptables path is injected at compile time via -DREAL_IPTABLES=... */
#ifndef REAL_IPTABLES
#error "REAL_IPTABLES must be defined at compile time"
#endif

int main(int argc, char **argv) {
    if (setuid(0) != 0) {
        fprintf(stderr, "iptables-suid-wrapper: setuid(0) failed: %s\n", strerror(errno));
        return 111;
    }
    argv[0] = REAL_IPTABLES;
    execve(REAL_IPTABLES, argv, environ);
    fprintf(stderr, "iptables-suid-wrapper: execve failed: %s\n", strerror(errno));
    return 1;
}
