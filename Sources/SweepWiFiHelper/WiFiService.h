#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@protocol SweepWiFiService
- (void)openLinkWithReply:(void (^)(NSString *_Nullable interfaceName, NSString *_Nullable error))reply;
@end
NS_ASSUME_NONNULL_END
