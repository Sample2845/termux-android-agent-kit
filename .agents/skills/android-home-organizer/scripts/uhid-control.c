/* Temporary Android UHID touchscreen and keyboard. No elevated privileges. */
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uhid.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Report 1: tip, contact ID, absolute X/Y, contact count.
 * Contact ID and count enable direct multitouch classification.
 * Report 2: modifiers, reserved byte, six keyboard usages. */
static const unsigned char descriptor[] = {
    5,13,9,4,161,1,133,1,9,34,161,2,9,66,21,0,37,1,117,1,149,1,
    129,2,117,7,149,1,129,3,9,81,117,8,149,1,37,127,129,2,5,1,
    9,48,9,49,21,0,38,255,127,117,16,149,2,129,2,192,5,13,9,84,
    117,8,149,1,37,1,129,2,192,
    5,1,9,6,161,1,133,2,5,7,25,224,41,231,21,0,37,1,117,1,
    149,8,129,2,149,1,117,8,129,3,149,6,117,8,21,0,37,101,
    5,7,25,0,41,101,129,0,192
};
static volatile sig_atomic_t stopping;
static void stop(int sig) { (void)sig; stopping = 1; }
static int emit(int fd, const struct uhid_event *event) {
    ssize_t n;
    do { n = write(fd, event, sizeof(*event)); } while (n < 0 && errno == EINTR);
    if (n != (ssize_t)sizeof(*event)) { perror("UHID write"); return -1; }
    return 0;
}
int main(void) {
    struct sigaction sa = {0};
    sa.sa_handler = stop;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    setbuf(stdout, NULL);
    int fd = open("/dev/uhid", O_RDWR | O_NONBLOCK);
    if (fd < 0) { perror("UHID open"); return 1; }
    struct uhid_event e = {0};
    e.type = UHID_CREATE2;
    strcpy((char *)e.u.create2.name, "Home Organizer Control");
    e.u.create2.rd_size = sizeof(descriptor);
    memcpy(e.u.create2.rd_data, descriptor, sizeof(descriptor));
    e.u.create2.bus = BUS_VIRTUAL;
    if (emit(fd, &e)) { close(fd); return 1; }
    puts("ready");
    char line[128], kind, extra;
    int a, b, c, result = 0;
    while (!stopping && fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, " %c %d %d %d %c", &kind, &a, &b, &c, &extra) != 4 ||
            !((kind == 't' && a >= 0 && a <= 1 && b >= 0 && b <= 32767 && c >= 0 && c <= 32767) ||
              (kind == 'k' && a >= 0 && a <= 255 && b >= 0 && b <= 101 && c == 0))) {
            fputs("Invalid input report\n", stderr); result = 2; break;
        }
        memset(&e, 0, sizeof(e)); e.type = UHID_INPUT2;
        unsigned char *d = e.u.input2.data;
        if (kind == 't') {
            e.u.input2.size = 8; d[0] = 1; d[1] = a; d[2] = 0;
            d[3] = b & 255; d[4] = b >> 8; d[5] = c & 255; d[6] = c >> 8; d[7] = a;
        } else {
            e.u.input2.size = 9; d[0] = 2; d[1] = a; d[3] = b;
        }
        if (emit(fd, &e)) { result = 1; break; }
        puts("ok");
    }
    memset(&e, 0, sizeof(e)); e.type = UHID_DESTROY;
    if (emit(fd, &e)) result = 1;
    close(fd);
    return result;
}
