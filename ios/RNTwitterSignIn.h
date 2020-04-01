#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <Foundation/Foundation.h>
dispatch_queue_t backgroundQueue;
@interface RNTwitterSignIn : NSObject <RCTBridgeModule>
@property (strong, nonatomic) AVAssetWriter *videoWriter;
@end
