//
//  LibVNCWrapper.h
//  VirtualControlRoom
//
//  Objective-C wrapper for LibVNCClient C library
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@protocol LibVNCWrapperDelegate <NSObject>
- (void)vncDidConnect;
- (void)vncDidDisconnect;
- (void)vncDidFailWithError:(NSString *)error;
- (void)vncDidUpdateFramebuffer:(CGImageRef)image;
- (void)vncDidResize:(CGSize)newSize;
- (NSString * _Nullable)vncPasswordForAuthentication;
- (void)vncRequiresPassword;
@end

@interface LibVNCWrapper : NSObject

@property (nonatomic, weak) id<LibVNCWrapperDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) CGSize screenSize;

- (BOOL)connectToHost:(NSString *)host 
                 port:(NSInteger)port 
             username:(nullable NSString *)username
             password:(nullable NSString *)password;
- (void)disconnect;
- (void)sendKeyEvent:(uint32_t)keysym down:(BOOL)down;
- (void)sendPointerEvent:(NSInteger)x y:(NSInteger)y buttonMask:(NSInteger)mask;

@end

NS_ASSUME_NONNULL_END