/* Generic SUID-root wrapper.
   Compile: gcc -DTARGET='"/path/to/real/binary"' -o wrapper_name suid-wrapper.c
   Install: chown root:root wrapper_name && chmod u+s wrapper_name

   When executed, this wrapper sets real UID to 0, then exec's TARGET.
   This is needed because some programs (e.g. iptables) check getuid() != 0
   and refuse to run when only euid=0 (plain SUID) is set. */
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

extern char **environ;

#ifndef TARGET
#error "TARGET must be defined (-DTARGET='\"/path/to/binary\"')"
#endif

int main(int argc, char **argv) {
    if (setgid(0) != 0) {
        fprintf(stderr, "suid-wrapper: setgid(0) failed: %s\n", strerror(errno));
        return 111;
    }
    if (setuid(0) != 0) {
        fprintf(stderr, "suid-wrapper: setuid(0) failed: %s\n", strerror(errno));
        return 111;
    }
    execve(TARGET, argv, environ);
    fprintf(stderr, "suid-wrapper: execve(%s) failed: %s\n", TARGET, strerror(errno));
    return 1;
}
