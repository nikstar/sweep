#import "SocketOwner.h"
#import <arpa/inet.h>
#import <libproc.h>
#import <netinet/tcp_fsm.h>
#import <time.h>

static NSData *socketKey(uint8_t protocol, uint16_t local, uint32_t remote, uint16_t port) {
    uint8_t key[9] = {protocol};
    memcpy(key + 1, &local, 2);
    memcpy(key + 3, &remote, 4);
    memcpy(key + 7, &port, 2);
    return [NSData dataWithBytes:key length:sizeof(key)];
}

@implementation SocketOwner {
    pid_t _pid;
    uint64_t _startSeconds, _startMicros, _lastScan;
    NSSet<NSData *> *_sockets, *_listeners;
}

- (instancetype)initWithPID:(pid_t)pid {
    if ((self = [super init])) {
        struct proc_bsdinfo info = {};
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info))
            return nil;
        _pid = pid;
        _startSeconds = info.pbi_start_tvsec;
        _startMicros = info.pbi_start_tvusec;
    }
    return self;
}

- (void)refresh:(uint32_t)guest {
    NSMutableSet *sockets = [NSMutableSet set], *listeners = [NSMutableSet set];
    _sockets = sockets;
    _listeners = listeners;
    struct proc_bsdinfo process = {};
    if (proc_pidinfo(_pid, PROC_PIDTBSDINFO, 0, &process, sizeof(process)) != sizeof(process) ||
        process.pbi_start_tvsec != _startSeconds || process.pbi_start_tvusec != _startMicros)
        return;

    int needed = proc_pidinfo(_pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (needed <= 0 || needed > 16 * 1024 * 1024)
        return;
    NSMutableData *storage = [NSMutableData dataWithLength:needed + 32 * sizeof(struct proc_fdinfo)];
    struct proc_fdinfo *fds = storage.mutableBytes;
    int bytes = proc_pidinfo(_pid, PROC_PIDLISTFDS, 0, fds, (int)storage.length);
    for (int i = 0; i < bytes / (int)sizeof(*fds); ++i) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET)
            continue;
        struct socket_fdinfo fd = {};
        if (proc_pidfdinfo(_pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &fd, sizeof(fd)) != sizeof(fd))
            continue;
        struct socket_info *socket = &fd.psi;
        if (socket->soi_family != AF_INET && socket->soi_family != AF_INET6)
            continue;
        BOOL tcp = socket->soi_kind == SOCKINFO_TCP;
        if (!tcp && (socket->soi_kind != SOCKINFO_IN || socket->soi_protocol != IPPROTO_UDP))
            continue;
        struct in_sockinfo *in = tcp ? &socket->soi_proto.pri_tcp.tcpsi_ini : &socket->soi_proto.pri_in;
        uint16_t local = ntohs((uint16_t)in->insi_lport), peer = ntohs((uint16_t)in->insi_fport);
        uint32_t src = in->insi_laddr.ina_46.i46a_addr4.s_addr;
        uint32_t dst = in->insi_faddr.ina_46.i46a_addr4.s_addr;
        if (!local || (src && src != guest))
            continue;
        if (socket->soi_family == AF_INET6 && !IN6_IS_ADDR_UNSPECIFIED(&in->insi_laddr.ina_6) &&
            !IN6_IS_ADDR_V4MAPPED(&in->insi_laddr.ina_6))
            continue;
        NSData *key = socketKey(tcp ? IPPROTO_TCP : IPPROTO_UDP, local, dst, peer);
        if (tcp && socket->soi_proto.pri_tcp.tcpsi_state == TCPS_LISTEN) {
            [listeners addObject:key];
        } else {
            [sockets addObject:key];
        }
    }
}

- (BOOL)allowsProtocol:(uint8_t)protocol
             localPort:(uint16_t)localPort
                remote:(uint32_t)remote
            remotePort:(uint16_t)remotePort
          guestAddress:(uint32_t)guestAddress
              incoming:(BOOL)incoming {
    uint64_t t = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    NSData *peer = socketKey(protocol, localPort, remote, remotePort);
    NSData *wildcard = socketKey(protocol, localPort, 0, 0);
    BOOL (^contains)(void) = ^BOOL {
        return [self->_sockets containsObject:peer] ||
               (protocol == IPPROTO_UDP && [self->_sockets containsObject:wildcard]) ||
               (incoming && [self->_listeners containsObject:wildcard]);
    };
    // Refresh periodically and on the first packet from a new socket. Bound the work when
    // other processes or unsolicited LAN traffic target the private interface.
    uint64_t age = t - _lastScan;
    if (age < NSEC_PER_SEC / 2 && contains())
        return YES;
    if (age < NSEC_PER_MSEC * 20)
        return NO;
    _lastScan = t;
    [self refresh:guestAddress];
    return contains();
}
@end
