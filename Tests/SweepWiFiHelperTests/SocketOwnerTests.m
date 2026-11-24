#import "SocketOwner.h"
#import <XCTest/XCTest.h>
#import <arpa/inet.h>
#import <unistd.h>

@interface SocketOwnerTests : XCTestCase
@end
@implementation SocketOwnerTests
- (void)testNewPeersMayUseAnOwnedDatagramSocketButNotAnUnownedPort {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr = {
        .sin_len = sizeof(addr), .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    XCTAssertEqual(bind(fd, (struct sockaddr *)&addr, sizeof(addr)), 0);
    socklen_t len = sizeof(addr);
    XCTAssertEqual(getsockname(fd, (struct sockaddr *)&addr, &len), 0);
    SocketOwner *owner = [[SocketOwner alloc] initWithPID:getpid()];
    for (const char **ip = (const char *[]){"192.0.2.1", "198.51.100.23", NULL}; *ip; ip++) {
        XCTAssertTrue([owner allowsProtocol:IPPROTO_UDP
                                  localPort:ntohs(addr.sin_port)
                                     remote:inet_addr(*ip)
                                 remotePort:6881
                               guestAddress:addr.sin_addr.s_addr
                                   incoming:NO]);
    }
    NSTask *other = [NSTask new];
    other.executableURL = [NSURL fileURLWithPath:@"/bin/sleep"];
    other.arguments = @[ @"10" ];
    XCTAssertTrue([other launchAndReturnError:nil]);
    SocketOwner *otherOwner = [[SocketOwner alloc] initWithPID:other.processIdentifier];
    XCTAssertNotNil(otherOwner);
    XCTAssertFalse([otherOwner allowsProtocol:IPPROTO_UDP
                                    localPort:ntohs(addr.sin_port)
                                       remote:inet_addr("192.0.2.1")
                                   remotePort:6881
                                 guestAddress:addr.sin_addr.s_addr
                                     incoming:NO]);
    [other terminate];
    [other waitUntilExit];
    close(fd);
}
@end
