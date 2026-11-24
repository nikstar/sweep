#import <Foundation/Foundation.h>

/// A snapshot of IPv4-capable sockets owned by the authenticated XPC client.
@interface SocketOwner : NSObject
- (instancetype)initWithPID:(pid_t)pid;
- (BOOL)allowsProtocol:(uint8_t)protocol
             localPort:(uint16_t)localPort
                remote:(uint32_t)remote
            remotePort:(uint16_t)remotePort
          guestAddress:(uint32_t)guestAddress
              incoming:(BOOL)incoming;
@end
