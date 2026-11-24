#import <Foundation/Foundation.h>

/// Owns an ephemeral, IPv4-only interface backed by a bridged Wi-Fi guest.
@interface DirectLink : NSObject
@property(nonatomic, copy) void (^disconnected)(void);
- (instancetype)initWithClientPID:(pid_t)pid;
- (void)start:(void (^)(NSString *interface, NSString *error))reply;
- (void)stop;
@end
