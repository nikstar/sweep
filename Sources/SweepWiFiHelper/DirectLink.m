#import "DirectLink.h"
#import "SocketOwner.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <net/ethernet.h>
#import <net/if.h>
#import <net/if_utun.h>
#import <netinet/if_ether.h>
#import <sys/ioctl.h>
#import <sys/kern_control.h>
#import <sys/sys_domain.h>
#import <sys/uio.h>
#import <time.h>
#import <unistd.h>
#import <vmnet/vmnet.h>

typedef struct {
    uint8_t bytes[6];
} MAC;
static const MAC broadcast = {{255, 255, 255, 255, 255, 255}};
static uint16_t read16(const uint8_t *p) { return (p[0] << 8) | p[1]; }
static void put16(uint8_t *p, uint16_t value) {
    p[0] = value >> 8;
    p[1] = value;
}
static uint32_t readIP(const uint8_t *p) {
    uint32_t ip;
    memcpy(&ip, p, 4);
    return ip;
}
static void putIP(uint8_t *p, uint32_t ip) { memcpy(p, &ip, 4); }
static NSString *address(uint32_t ip) {
    char text[INET_ADDRSTRLEN];
    return @(inet_ntop(AF_INET, &ip, text, sizeof(text)));
}
static BOOL usableIP(uint32_t ip) {
    uint32_t a = ntohl(ip);
    return (a >> 24) != 0 && (a >> 24) != 127 && (a >> 28) < 14;
}
static uint16_t checksum(const uint8_t *p, size_t n) {
    uint32_t sum = 0;
    for (size_t i = 0; i < n; i += 2)
        sum += read16(p + i);
    while (sum >> 16)
        sum = (sum & 65535) + (sum >> 16);
    return (uint16_t)~sum;
}
static uint64_t now(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / NSEC_PER_SEC; }

static BOOL command(NSString *path, NSArray<NSString *> *args) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = args;
    if (![task launchAndReturnError:nil])
        return NO;
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

static NSString *wifiInterface(void) {
    NSArray *interfaces = CFBridgingRelease(SCNetworkInterfaceCopyAll());
    xpc_object_t supported = vmnet_copy_shared_interface_list();
    if (!supported)
        return nil;
    for (id item in interfaces) {
        SCNetworkInterfaceRef iface = (__bridge SCNetworkInterfaceRef)item;
        if (!CFEqual(SCNetworkInterfaceGetInterfaceType(iface), kSCNetworkInterfaceTypeIEEE80211))
            continue;
        NSString *name = (__bridge NSString *)SCNetworkInterfaceGetBSDName(iface);
        for (size_t i = 0; i < xpc_array_get_count(supported); i++) {
            const char *physical = xpc_array_get_string(supported, i);
            if (physical && [name isEqualToString:@(physical)])
                return name;
        }
    }
    return nil;
}

// DHCP on the guest must not turn an unrelated or pre-existing host address into a local route.
static BOOL allowedGuest(NSString *wifi, uint32_t candidate, uint32_t router, BOOL alreadyAssigned) {
    if (!usableIP(candidate) || !usableIP(router) || candidate == router)
        return NO;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list))
        return NO;
    BOOL subnet = NO, collision = NO;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET)
            continue;
        uint32_t local = ((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr;
        if (local == candidate && !alreadyAssigned)
            collision = YES;
        if (strcmp(i->ifa_name, wifi.UTF8String) || !i->ifa_netmask || !(i->ifa_flags & IFF_RUNNING))
            continue;
        uint32_t mask = ((struct sockaddr_in *)i->ifa_netmask)->sin_addr.s_addr;
        subnet |= mask && (local & mask) == (candidate & mask) && (local & mask) == (router & mask) &&
                  (candidate & ~mask) != 0 && (candidate | mask) != UINT32_MAX && local != candidate;
    }
    freeifaddrs(list);
    return subnet && !collision;
}

@implementation DirectLink {
    dispatch_queue_t _queue;
    dispatch_source_t _tick, _reader;
    interface_ref _vm;
    MAC _mac, _routerMAC;
    uint32_t _xid, _offered, _server, _ip, _router;
    uint64_t _deadline, _renew, _expiry, _nextDHCP, _nextARP;
    BOOL _stopped, _hasRouter;
    int _fd;
    SocketOwner *_owner;
    NSString *_interface, *_wifi;
    NSMutableDictionary<NSData *, NSNumber *> *_fragments;
    uint64_t _nextPrune, _nextNetworkCheck;
    void (^_reply)(NSString *, NSString *);
}
- (instancetype)initWithClientPID:(pid_t)pid {
    if ((self = [super init])) {
        _fd = -1;
        _owner = [[SocketOwner alloc] initWithPID:pid];
        if (!_owner)
            return nil;
        _queue = dispatch_queue_create("me.nikstar.sweep.wifi.link",
                                       dispatch_queue_attr_make_with_autorelease_frequency(
                                           DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM));
    }
    return self;
}
- (void)start:(void (^)(NSString *, NSString *))reply {
    dispatch_async(_queue, ^{
        if (self->_stopped || self->_vm) {
            reply(nil, @"Wi-Fi link already closed or starting.");
            return;
        }
        self->_reply = [reply copy];
        NSString *name = wifiInterface();
        self->_wifi = name;
        self->_fragments = [NSMutableDictionary new];
        if (!name) {
            [self end:@"macOS has no bridge-capable Wi-Fi interface."];
            return;
        }
        xpc_object_t desc = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_uint64(desc, vmnet_operation_mode_key, VMNET_BRIDGED_MODE);
        xpc_dictionary_set_string(desc, vmnet_shared_interface_name_key, name.UTF8String);
        self->_deadline = now() + 18;
        self->_tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
        dispatch_source_set_timer(self->_tick, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(self->_tick, ^{
            [self timer];
        });
        dispatch_activate(self->_tick);
        self->_vm = vmnet_start_interface(desc, self->_queue, ^(vmnet_return_t status, xpc_object_t params) {
            if (self->_stopped)
                return;
            const char *mac = params ? xpc_dictionary_get_string(params, vmnet_mac_address_key) : NULL;
            struct ether_addr *ea = mac ? ether_aton(mac) : NULL;
            if (status != VMNET_SUCCESS || !ea) {
                [self end:[NSString stringWithFormat:@"Could not bridge to Wi-Fi (vmnet %d).", status]];
                return;
            }
            memcpy(&self->_mac, ea, 6);
            self->_xid = arc4random_uniform(UINT32_MAX) + 1;
            vmnet_return_t subscribed =
                vmnet_interface_set_event_callback(self->_vm, VMNET_INTERFACE_PACKETS_AVAILABLE, self->_queue,
                                                   ^(interface_event_t event, xpc_object_t info) {
                                                       if (!self->_stopped)
                                                           [self receiveFrames];
                                                   });
            if (subscribed != VMNET_SUCCESS) {
                [self end:@"Could not receive Wi-Fi frames."];
                return;
            }
            [self timer];
        });
        if (!self->_vm)
            [self end:@"macOS could not start the Wi-Fi bridge."];
    });
}
- (void)stop {
    dispatch_async(_queue, ^{
        [self end:@"Wi-Fi connection closed."];
    });
}
- (void)end:(NSString *)message {
    if (_stopped)
        return;
    _stopped = YES;
    if (_vm && _ip && _hasRouter)
        [self sendDHCPType:7];
    if (_tick) {
        dispatch_source_cancel(_tick);
        _tick = nil;
    }
    if (_reader) {
        dispatch_source_cancel(_reader);
        _reader = nil;
    }
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
    if (_vm) {
        vmnet_interface_set_event_callback(_vm, 0, NULL, NULL);
        vmnet_stop_interface(_vm, _queue,
                             ^(vmnet_return_t status){
                             });
        _vm = NULL;
    }
    if (_reply) {
        _reply(nil, message);
        _reply = nil;
    } else if (self.disconnected)
        self.disconnected();
    self.disconnected = nil;
}
- (void)timer {
    uint64_t t = now();
    if ((!_interface && t >= _deadline) || (_expiry && t >= _expiry)) {
        [self end:@"Wi-Fi did not provide or renew a DHCP address."];
        return;
    }
    if (!_xid)
        return;
    if (_ip && t >= _nextNetworkCheck) {
        _nextNetworkCheck = t + 5;
        if (!allowedGuest(_wifi, _ip, _router, YES)) {
            [self end:@"The Wi-Fi network changed."];
            return;
        }
    }
    if (t >= _nextPrune) {
        _nextPrune = t + 10;
        for (NSData *key in _fragments.allKeys) {
            if ([_fragments[key] unsignedLongLongValue] <= t)
                [_fragments removeObjectForKey:key];
        }
    }
    if ((!_ip || t >= _renew) && t >= _nextDHCP) {
        [self sendDHCPType:(_offered || _ip) ? 3 : 1];
        _nextDHCP = t + 3;
    }
    if (_ip && t >= _nextARP) {
        [self arpTo:broadcast target:_router reply:NO];
        _nextARP = t + (_hasRouter ? 30 : 1);
    }
}
- (void)frame:(const uint8_t *)payload length:(size_t)n type:(uint16_t)type to:(MAC)dest {
    if (!_vm || n > 1500)
        return;
    uint8_t header[14];
    memcpy(header, &dest, 6);
    memcpy(header + 6, &_mac, 6);
    put16(header + 12, type);
    struct iovec vec[2] = {{header, sizeof(header)}, {(void *)payload, n}};
    struct vmpktdesc packet = {sizeof(header) + n, vec, 2, 0};
    int count = 1;
    vmnet_write(_vm, &packet, &count);
}
- (void)sendDHCPType:(uint8_t)type {
    // BOOTP with the broadcast flag so a guest without an address can receive the reply.
    uint8_t p[328] = {0}, *udp = p + 20, *b = udp + 8;
    p[0] = 0x45;
    put16(p + 2, sizeof(p));
    p[8] = 64;
    p[9] = IPPROTO_UDP;
    putIP(p + 12, _ip);
    putIP(p + 16, type == 7 ? _server : INADDR_BROADCAST);
    put16(p + 10, checksum(p, 20));
    put16(udp, 68);
    put16(udp + 2, 67);
    put16(udp + 4, sizeof(p) - 20);
    b[0] = 1;
    b[1] = 1;
    b[2] = 6;
    putIP(b + 4, _xid);
    put16(b + 10, type == 7 ? 0 : 0x8000);
    putIP(b + 12, _ip);
    memcpy(b + 28, &_mac, 6);
    putIP(b + 236, htonl(0x63825363));
    uint8_t *o = b + 240;
    *o++ = 53;
    *o++ = 1;
    *o++ = type;
    if (_offered && !_ip) {
        *o++ = 50;
        *o++ = 4;
        putIP(o, _offered);
        o += 4;
    }
    if (type == 7 || (_offered && !_ip)) {
        *o++ = 54;
        *o++ = 4;
        putIP(o, _server);
        o += 4;
    }
    *o++ = 55;
    *o++ = 3;
    *o++ = 3;
    *o++ = 51;
    *o++ = 54;
    *o = 255;
    [self frame:p length:sizeof(p) type:ETHERTYPE_IP to:type == 7 ? _routerMAC : broadcast];
}
- (void)dhcp:(const uint8_t *)b length:(size_t)n {
    if (n < 240 || b[0] != 2 || b[1] != 1 || b[2] != 6 || readIP(b + 4) != _xid || memcmp(b + 28, &_mac, 6) ||
        ntohl(readIP(b + 236)) != 0x63825363)
        return;
    uint8_t type = 0;
    uint32_t server = 0, router = 0, lease = 0;
    for (size_t i = 240; i < n;) {
        uint8_t k = b[i++];
        if (!k)
            continue;
        if (k == 255)
            break;
        if (i >= n)
            return;
        size_t len = b[i++];
        if (len > n - i)
            return;
        if (k == 53 && len == 1)
            type = b[i];
        if (k == 54 && len == 4)
            server = readIP(b + i);
        if (k == 3 && len >= 4)
            router = readIP(b + i);
        if (k == 51 && len == 4)
            lease = ntohl(readIP(b + i));
        i += len;
    }
    uint32_t offered = readIP(b + 16);
    if (type == 2 && !_offered && !_ip && usableIP(offered) && usableIP(server)) {
        _offered = offered;
        _server = server;
        [self sendDHCPType:3];
        return;
    }
    if (!server || server != _server)
        return;
    if (type == 6) {
        [self end:@"The Wi-Fi DHCP server withdrew the lease."];
        return;
    }
    if (!router && _ip)
        router = _router;
    if (type != 5 || offered != _offered || !lease || !allowedGuest(_wifi, offered, router, _ip != 0))
        return;
    if (_ip && (_ip != offered || router != _router)) {
        [self end:@"The Wi-Fi network changed."];
        return;
    }
    _ip = offered;
    _router = router;
    _expiry = now() + lease;
    _renew = now() + MAX(1, lease / 2);
    [self timer];
}
- (void)arpTo:(MAC)dst target:(uint32_t)ip reply:(BOOL)reply {
    uint8_t a[28] = {0};
    put16(a, 1);
    put16(a + 2, ETHERTYPE_IP);
    a[4] = 6;
    a[5] = 4;
    put16(a + 6, reply ? 2 : 1);
    memcpy(a + 8, &_mac, 6);
    putIP(a + 14, _ip);
    if (reply)
        memcpy(a + 18, &dst, 6);
    putIP(a + 24, ip);
    [self frame:a length:sizeof(a) type:ETHERTYPE_ARP to:dst];
}
// The host kernel also has wildcard listeners. Admit replies to guest-originated
// TCP/UDP flows and the torrent engine’s own listeners.
- (BOOL)allowPacket:(const uint8_t *)ip length:(size_t)n outgoing:(BOOL)out {
    if (n < 20 || (ip[0] >> 4) != 4 || !usableIP(readIP(ip + (out ? 16 : 12))))
        return NO;
    size_t hdr = (ip[0] & 15) * 4;
    if (hdr < 20 || hdr > n || (ip[9] != IPPROTO_TCP && ip[9] != IPPROTO_UDP))
        return NO;
    uint8_t key[9] = {0};
    memcpy(key, ip + (out ? 16 : 12), 4);
    key[8] = ip[9];
    uint16_t frag = read16(ip + 6);
    uint64_t t = now();
    NSData *fragmentKey = nil;
    if (frag & 0x3fff) {
        uint8_t fragment[8] = {0};
        memcpy(fragment, key, 4);
        memcpy(fragment + 4, ip + 4, 2);
        fragment[6] = ip[9];
        fragment[7] = out;
        fragmentKey = [NSData dataWithBytes:fragment length:sizeof(fragment)];
        if (frag & 0x1fff)
            return [_fragments[fragmentKey] unsignedLongLongValue] > t;
    }
    if (n < hdr + (ip[9] == IPPROTO_TCP ? 20 : 8))
        return NO;
    memcpy(key + 4, ip + hdr + (out ? 0 : 2), 2);
    memcpy(key + 6, ip + hdr + (out ? 2 : 0), 2);
    if (![_owner allowsProtocol:ip[9]
                      localPort:read16(key + 4)
                         remote:readIP(key)
                     remotePort:read16(key + 6)
                   guestAddress:_ip
                       incoming:(!out || (ip[9] == IPPROTO_TCP && (ip[hdr + 13] & 0x12) == 0x12))])
        return NO;
    if (fragmentKey && _fragments.count < 1024)
        _fragments[fragmentKey] = @(t + 15);
    return YES;
}
- (void)receiveFrames {
    uint8_t f[65536];
    for (int i = 0; i < 128 && !_stopped; i++) {
        struct iovec v = {f, sizeof(f)};
        struct vmpktdesc p = {sizeof(f), &v, 1, 0};
        int count = 1;
        if (vmnet_read(_vm, &p, &count) != VMNET_SUCCESS || !count)
            return;
        size_t n = p.vm_pkt_size;
        if (n < 14 || n > sizeof(f))
            continue;
        const uint8_t *b = f + 14;
        n -= 14;
        if (read16(f + 12) == ETHERTYPE_ARP && _ip && n >= 28 && read16(b) == 1 &&
            read16(b + 2) == ETHERTYPE_IP && b[4] == 6 && b[5] == 4 && readIP(b + 24) == _ip) {
            MAC sender;
            memcpy(&sender, b + 8, 6);
            if (memcmp(&sender, f + 6, 6) || (sender.bytes[0] & 1))
                continue;
            if (read16(b + 6) == 1)
                [self arpTo:sender target:readIP(b + 14) reply:YES];
            if (read16(b + 6) == 2 && readIP(b + 14) == _router && !memcmp(b + 18, &_mac, 6)) {
                _routerMAC = sender;
                _hasRouter = YES;
                if (!_interface && ![self openTunnel])
                    [self end:@"Could not create Sweep’s private IPv4 interface."];
            }
            continue;
        }
        if (read16(f + 12) != ETHERTYPE_IP || n < 20 || (b[0] >> 4) != 4)
            continue;
        size_t ihl = (b[0] & 15) * 4, len = read16(b + 2);
        if (ihl < 20 || len < ihl || len > n)
            continue;
        if (b[9] == IPPROTO_UDP && !(read16(b + 6) & 0x3fff) && len >= ihl + 8 && read16(b + ihl) == 67 &&
            read16(b + ihl + 2) == 68) {
            size_t udpLen = read16(b + ihl + 4);
            if (udpLen >= 8 && udpLen <= len - ihl)
                [self dhcp:b + ihl + 8 length:udpLen - 8];
        } else if (_fd >= 0 && readIP(b + 16) == _ip && !memcmp(f, &_mac, 6) &&
                   [self allowPacket:b length:len outgoing:NO]) {
            uint32_t family = htonl(AF_INET);
            struct iovec vec[2] = {{&family, 4}, {(void *)b, len}};
            writev(_fd, vec, 2);
        }
    }
}
- (BOOL)openTunnel {
    _fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
    if (_fd < 0)
        return NO;
    struct ctl_info ctl = {0};
    strlcpy(ctl.ctl_name, UTUN_CONTROL_NAME, sizeof(ctl.ctl_name));
    if (ioctl(_fd, CTLIOCGINFO, &ctl) < 0)
        return NO;
    struct sockaddr_ctl sc = {0};
    sc.sc_len = sizeof(sc);
    sc.sc_family = AF_SYSTEM;
    sc.ss_sysaddr = AF_SYS_CONTROL;
    sc.sc_id = ctl.ctl_id;
    if (connect(_fd, (struct sockaddr *)&sc, sizeof(sc)) < 0)
        return NO;
    char name[IFNAMSIZ] = {0};
    socklen_t size = sizeof(name);
    if (getsockopt(_fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, name, &size) < 0)
        return NO;
    fcntl(_fd, F_SETFL, O_NONBLOCK);
    fcntl(_fd, F_SETFD, FD_CLOEXEC);
    NSString *iface = @(name), *ip = address(_ip);
    // A /32 on the disposable guest interface never publishes a LAN subnet or DNS service.
    if (!command(@"/sbin/ifconfig",
                 @[ iface, @"inet", ip, ip, @"netmask", @"255.255.255.255", @"mtu", @"1400", @"up" ]))
        return NO;
    for (NSString *net in @[ @"0.0.0.0/2", @"64.0.0.0/2", @"128.0.0.0/2", @"192.0.0.0/2" ]) {
        if (!command(@"/sbin/route",
                     @[ @"-n", @"add", @"-net", @"-ifscope", iface, net, @"-interface", iface ]))
            return NO;
    }
    _interface = iface;
    _reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _fd, 0, _queue);
    dispatch_source_set_event_handler(_reader, ^{
        uint8_t p[2048];
        for (int i = 0; i < 128 && !self->_stopped; i++) {
            ssize_t n = read(self->_fd, p, sizeof(p));
            if (n <= 0)
                break;
            if (n >= 24 && readIP(p) == htonl(AF_INET) && (p[4] >> 4) == 4 && readIP(p + 16) == self->_ip &&
                read16(p + 6) == n - 4 && [self allowPacket:p + 4 length:n - 4 outgoing:YES])
                [self frame:p + 4 length:n - 4 type:ETHERTYPE_IP to:self->_routerMAC];
        }
    });
    dispatch_activate(_reader);
    if (_reply) {
        _reply(iface, nil);
        _reply = nil;
    }
    return YES;
}
@end
