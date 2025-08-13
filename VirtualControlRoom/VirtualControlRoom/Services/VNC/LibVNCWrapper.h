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
- (void)vncDidFailWithDetailedError:(NSString *)error libVNCError:(nullable NSString *)libVNCError errnoValue:(int)errnoValue errnoString:(nullable NSString *)errnoString;
- (void)vncDidUpdateFramebuffer:(CGImageRef)image;
- (void)vncDidResize:(CGSize)newSize;
- (NSString * _Nullable)vncPasswordForAuthentication;
- (void)vncRequiresPassword;
- (void)vncRequiresCredentialsWithType:(int)credentialType;
- (NSString * _Nullable)vncUsernameForAuthentication;
- (NSString * _Nullable)vncPasswordForUserAuthentication;

// Security negotiation diagnostics
- (void)vncSecurityNegotiationStarted:(NSArray<NSNumber *> *)serverSecurityTypes clientSecurityTypes:(NSArray<NSNumber *> *)clientSecurityTypes;
- (void)vncSecurityTypeSelected:(int)securityType;
- (void)vncLibVNCLogMessage:(NSString *)message level:(NSString *)level;
- (void)vncServerReasonMessage:(NSString *)reason;
@end

@interface LibVNCWrapper : NSObject

@property (nonatomic, weak) id<LibVNCWrapperDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) CGSize screenSize;
@property (nonatomic) NSUInteger framebufferUpdateCount;

- (BOOL)connectToHost:(NSString *)host 
                 port:(NSInteger)port 
             username:(nullable NSString *)username
             password:(nullable NSString *)password;
- (void)disconnect;
- (void)sendKeyEvent:(uint32_t)keysym down:(BOOL)down;
- (void)sendPointerEvent:(NSInteger)x y:(NSInteger)y buttonMask:(NSInteger)mask;

@end

NS_ASSUME_NONNULL_END