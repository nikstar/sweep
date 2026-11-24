#import "DirectLink.h"
#import "WiFiService.h"
#import <Foundation/Foundation.h>

/// Each approved client owns exactly one link. XPC invalidation also covers a crashed app.
@interface WiFiClient : NSObject <SweepWiFiService>
@property(nonatomic) DirectLink *link;
@property(nonatomic, weak) NSXPCConnection *connection;
@property(nonatomic) BOOL closed;
- (void)close;
@end

@implementation WiFiClient
- (void)close {
    @synchronized(self) {
        self.closed = YES;
        [self.link stop];
    }
}
- (void)openLinkWithReply:(void (^)(NSString *, NSString *))reply {
    @synchronized(self) {
        if (self.closed || self.link) {
            reply(nil, @"A link already exists for this connection.");
            return;
        }
        self.link = [[DirectLink alloc] initWithClientPID:self.connection.processIdentifier];
        if (!self.link) {
            reply(nil, @"Could not identify the calling Sweep process.");
            return;
        }
        __weak NSXPCConnection *connection = self.connection;
        self.link.disconnected = ^{
            [connection invalidate];
        };
        [self.link start:reply];
    }
}
@end

@interface WiFiListener : NSObject <NSXPCListenerDelegate>
@property(nonatomic) NSUInteger clients;
- (void)exitWhenIdle;
@end
@implementation WiFiListener
// Also covers a wake triggered by a client rejected before delegate acceptance.
- (void)exitWhenIdle {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @synchronized(self) {
            if (self.clients == 0)
                exit(0);
        }
    });
}
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    WiFiClient *client = [WiFiClient new];
    client.connection = connection;
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SweepWiFiService)];
    connection.exportedObject = client;
    @synchronized(self) {
        self.clients++;
    }
    connection.invalidationHandler = ^{
        [client close];
        @synchronized(self) {
            self.clients--;
        }
        [self exitWhenIdle];
    };
    [connection resume];
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@"me.nikstar.sweep.wifi"];
        [listener
            setConnectionCodeSigningRequirement:@"anchor apple generic and identifier \"me.nikstar.sweep\" "
                                                @"and certificate leaf[subject.OU] = \"6RX8GEVB43\""];
        __attribute__((objc_precise_lifetime)) WiFiListener *delegate = [WiFiListener new];
        listener.delegate = delegate;
        [listener resume];
        [delegate exitWhenIdle];
        [[NSRunLoop currentRunLoop] run];
        (void)delegate;
    }
    return 0;
}
