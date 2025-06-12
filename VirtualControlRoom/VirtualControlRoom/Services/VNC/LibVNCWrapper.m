//
//  LibVNCWrapper.m
//  VirtualControlRoom
//
//  Objective-C wrapper for LibVNCClient C library
//

#import "LibVNCWrapper.h"
#import <rfb/rfbclient.h>
#import <errno.h>
#import <stdarg.h>

@interface LibVNCWrapper ()
@property (nonatomic, assign) rfbClient *client;
@property (nonatomic, strong) dispatch_queue_t vncQueue;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, strong) NSString *savedPassword;
@property (nonatomic, strong) NSThread *vncThread;
@property (nonatomic, strong) NSTimer *connectionTimeoutTimer;
@property (nonatomic, assign) BOOL hasReportedError;
@property (nonatomic, assign) BOOL shouldCancelConnection; // Flag to cancel connection
@property (nonatomic, strong) LibVNCWrapper *selfReference; // Keep strong ref during connection
@end

// C callback functions that forward to Objective-C methods
static void framebufferUpdateCallback(rfbClient* client, int x, int y, int w, int h);
static char* passwordCallback(rfbClient* client);
static void logCallback(const char *format, ...);
static rfbBool resizeCallback(rfbClient* client);

@implementation LibVNCWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _vncQueue = dispatch_queue_create("com.virtualcontrolroom.vnc", DISPATCH_QUEUE_SERIAL);
        _isConnected = NO;
        _screenSize = CGSizeZero;
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
}

- (BOOL)connectToHost:(NSString *)host 
                 port:(NSInteger)port 
             username:(NSString *)username
             password:(NSString *)password {
    
    // Reset flags for new connection
    self.hasReportedError = NO;
    self.shouldCancelConnection = NO;
    
    // Start timeout timer immediately
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connectionTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                                      target:self
                                                                    selector:@selector(connectionTimedOut:)
                                                                    userInfo:@{@"host": host, @"port": @(port)}
                                                                     repeats:NO];
    });
    
    // Keep strong reference to self during connection to prevent deallocation
    self.selfReference = self;
    
    // Store connection parameters
    NSString *hostCopy = [host copy];
    NSInteger portCopy = port;
    NSString *passwordCopy = [password copy];
    
    dispatch_async(self.vncQueue, ^{
        [self performConnectionWithHost:hostCopy port:portCopy password:passwordCopy];
    });
    
    return YES;
}

- (void)performConnectionWithHost:(NSString *)host port:(NSInteger)port password:(NSString *)password {
    // Early cancellation check
    if (self.shouldCancelConnection || self.hasReportedError) {
        NSLog(@"⚠️ VNC: Connection cancelled before starting");
        self.selfReference = nil;
        return;
    }
    
    NSLog(@"🔄 VNC: Starting connection process");
    
    // Create VNC client
    rfbClient *client = rfbGetClient(8, 3, 4);
    if (!client) {
        [self reportErrorIfNeeded:@"Failed to create VNC client"];
        return;
    }
    
    // Check for cancellation after client creation
    if (self.shouldCancelConnection || self.hasReportedError) {
        NSLog(@"⚠️ VNC: Connection cancelled during setup");
        rfbClientCleanup(client);
        self.selfReference = nil;
        return;
    }
    
    // Set up client
    client->clientData = (__bridge void *)self;
    self.client = client;
    self.savedPassword = password;
    
    // Set callbacks
    client->MallocFrameBuffer = resizeCallback;
    client->GotFrameBufferUpdate = framebufferUpdateCallback;
    client->GetPassword = passwordCallback;
    
    // Configure connection
    client->serverHost = strdup([host UTF8String]);
    client->serverPort = (int)port;
    client->connectTimeout = 30;
    
    // Set pixel format
    client->format.bitsPerPixel = 32;
    client->format.depth = 24;
    client->format.trueColour = 1;
    client->format.bigEndian = 0;
    client->format.redShift = 16;
    client->format.greenShift = 8;
    client->format.blueShift = 0;
    client->format.redMax = 255;
    client->format.greenMax = 255;
    client->format.blueMax = 255;
    
    NSLog(@"🚀 VNC: Calling rfbInitClient...");
    
    // The critical section - call rfbInitClient
    int argc = 0;
    char **argv = NULL;
    rfbBool initResult = rfbInitClient(client, &argc, argv);
    
    NSLog(@"🔍 VNC: rfbInitClient returned: %s", initResult ? "TRUE" : "FALSE");
    
    // Check state on main queue to avoid race conditions
    __block BOOL shouldProceed = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        shouldProceed = !self.hasReportedError && !self.shouldCancelConnection;
    });
    
    // Handle result - but only if we haven't already reported an error
    if (shouldProceed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Cancel timeout timer
            [self.connectionTimeoutTimer invalidate];
            self.connectionTimeoutTimer = nil;
        });
        
        if (initResult) {
            // Success
            self.isConnected = YES;
            self.selfReference = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.delegate && !self.hasReportedError) {
                    [self.delegate vncDidConnect];
                }
            });
            
            // Start event loop
            [self runEventLoop];
        } else {
            // Failure
            self.client = NULL; // Don't cleanup - rfbInitClient did that
            [self reportErrorIfNeeded:[NSString stringWithFormat:@"Unable to connect to VNC server at %@:%d", host, (int)port]];
        }
    } else {
        // We already reported an error (timeout) - just cleanup
        NSLog(@"⚠️ VNC: Ignoring rfbInitClient result - already reported error");
        if (self.client == client) {
            self.client = NULL;
        }
        self.selfReference = nil;
    }
}

- (void)disconnect {
    self.isConnected = NO;
    self.hasReportedError = NO;
    self.shouldCancelConnection = YES;
    
    // Cancel timer - handle main thread carefully
    if (self.connectionTimeoutTimer) {
        if ([NSThread isMainThread]) {
            [self.connectionTimeoutTimer invalidate];
            self.connectionTimeoutTimer = nil;
        } else {
            NSTimer *timer = self.connectionTimeoutTimer;
            self.connectionTimeoutTimer = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [timer invalidate];
            });
        }
    }
    
    if (self.client) {
        rfbClient *client = self.client;
        self.client = NULL;
        
        dispatch_async(self.vncQueue, ^{
            rfbClientCleanup(client);
        });
    }
    
    // Clear self reference LAST to allow deallocation after cleanup
    self.selfReference = nil;
}

- (void)connectionTimedOut:(NSTimer *)timer {
    NSLog(@"⏰ VNC: Connection timeout fired");
    
    if (!self.isConnected && !self.hasReportedError) {
        self.hasReportedError = YES;
        
        NSDictionary *userInfo = timer.userInfo;
        NSString *host = userInfo[@"host"];
        NSNumber *port = userInfo[@"port"];
        
        NSString *errorMsg = [NSString stringWithFormat:@"Connection timed out after 10 seconds. The server at %@:%@ is not responding.", host, port];
        
        // Store delegate reference before cleanup
        id<LibVNCWrapperDelegate> delegate = self.delegate;
        
        // Set cancellation flag and clean up the connection immediately
        self.shouldCancelConnection = YES;
        self.isConnected = NO;
        
        // Important: Keep selfReference alive if rfbInitClient is still running
        // It will be cleared when performConnectionWithHost completes
        
        if (self.client) {
            rfbClient *client = self.client;
            self.client = NULL;
            // Don't cleanup - rfbInitClient might still be using it
        }
        
        // Call delegate last to avoid potential deallocation issues
        if (delegate) {
            [delegate vncDidFailWithError:errorMsg];
        }
    }
    
    // Always invalidate the timer if it exists
    [self.connectionTimeoutTimer invalidate];
    self.connectionTimeoutTimer = nil;
}

- (void)sendKeyEvent:(uint32_t)keysym down:(BOOL)down {
    NSLog(@"🎹 LibVNCWrapper: sendKeyEvent keysym:0x%X down:%d", keysym, down);
    NSLog(@"   Connection state - client:%p isConnected:%d", self.client, self.isConnected);
    
    if (!self.client) {
        NSLog(@"❌ LibVNCWrapper: Cannot send key event - client is NULL");
        return;
    }
    
    if (!self.isConnected) {
        NSLog(@"❌ LibVNCWrapper: Cannot send key event - not connected");
        return;
    }
    
    rfbClient *client = self.client;
    
    // Try synchronous call for debugging
    NSLog(@"🎹 LibVNCWrapper: Sending key event synchronously");
    int result = SendKeyEvent(client, keysym, down ? TRUE : FALSE);
    NSLog(@"   SendKeyEvent result: %d", result);
    
    // Also send async for normal operation
    dispatch_async(self.vncQueue, ^{
        SendKeyEvent(client, keysym, down ? TRUE : FALSE);
    });
}

- (void)sendPointerEvent:(NSInteger)x y:(NSInteger)y buttonMask:(NSInteger)mask {
    NSLog(@"🟢 LibVNCWrapper: sendPointerEvent x:%ld y:%ld mask:%ld", (long)x, (long)y, (long)mask);
    NSLog(@"   Connection state - client:%p isConnected:%d vncQueue:%@", self.client, self.isConnected, self.vncQueue);
    
    if (!self.client) {
        NSLog(@"❌ LibVNCWrapper: Cannot send pointer event - client is NULL");
        return;
    }
    
    if (!self.isConnected) {
        NSLog(@"❌ LibVNCWrapper: Cannot send pointer event - not connected");
        return;
    }
    
    if (!self.vncQueue) {
        NSLog(@"❌ LibVNCWrapper: Cannot send pointer event - vncQueue is NULL");
        return;
    }
    
    // Capture client pointer before async block
    rfbClient *clientPtr = self.client;
    
    // Try synchronous call first to debug
    NSLog(@"🟣 LibVNCWrapper: Sending pointer event synchronously for debugging");
    int result = SendPointerEvent(clientPtr, (int)x, (int)y, (int)mask);
    NSLog(@"   SendPointerEvent result: %d", result);
    
    // Also try async for normal operation
    dispatch_async(self.vncQueue, ^{
        NSLog(@"🟣 LibVNCWrapper: Also sending on VNC queue");
        SendPointerEvent(clientPtr, (int)x, (int)y, (int)mask);
    });
}

#pragma mark - Internal Methods

- (void)handleFramebufferUpdate {
    NSLog(@"🖼️ LibVNCWrapper: handleFramebufferUpdate called");
    
    if (!self.client || !self.isConnected) {
        NSLog(@"⚠️ Cannot handle framebuffer update - client:%p connected:%d", self.client, self.isConnected);
        return;
    }
    
    rfbClient *client = self.client;
    
    // Create CGImage from framebuffer
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, 
                                                             client->frameBuffer, 
                                                             client->width * client->height * 4, 
                                                             NULL);
    
    CGImageRef image = CGImageCreate(client->width,
                                   client->height,
                                   8,  // bits per component
                                   32, // bits per pixel
                                   client->width * 4, // bytes per row
                                   colorSpace,
                                   kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
                                   provider,
                                   NULL,
                                   NO,
                                   kCGRenderingIntentDefault);
    
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    
    if (image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate vncDidUpdateFramebuffer:image];
            CGImageRelease(image);
        });
    }
}

- (void)runEventLoop {
    // Simple event loop without complex self management
    dispatch_async(self.vncQueue, ^{
        rfbClient *client = self.client;
        while (self.isConnected && client) {
            int result = WaitForMessage(client, 100000);
            if (result > 0) {
                if (!HandleRFBServerMessage(client)) {
                    break;
                }
            } else if (result < 0) {
                break;
            }
        }
        
        // Cleanup
        self.isConnected = NO;
        self.selfReference = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate) {
                [self.delegate vncDidDisconnect];
            }
        });
    });
}

- (void)reportErrorIfNeeded:(NSString *)error {
    if (!self.hasReportedError) {
        self.hasReportedError = YES;
        self.selfReference = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate) {
                [self.delegate vncDidFailWithError:error];
            }
        });
    }
}

@end

#pragma mark - C Callbacks

static void logCallback(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    // Create formatted string
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    // Remove trailing newline if present
    size_t len = strlen(buffer);
    if (len > 0 && buffer[len-1] == '\n') {
        buffer[len-1] = '\0';
    }
    
    NSString *message = [NSString stringWithUTF8String:buffer];
    NSLog(@"🔵 LibVNC: %@", message);
}

static void framebufferUpdateCallback(rfbClient* client, int x, int y, int w, int h) {
    LibVNCWrapper *wrapper = (__bridge LibVNCWrapper *)client->clientData;
    [wrapper handleFramebufferUpdate];
    
    // Request next update - continuous updates mode
    SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, TRUE);
}

static char* passwordCallback(rfbClient* client) {
    NSLog(@"🔐 VNC: Password callback called");
    LibVNCWrapper *wrapper = (__bridge LibVNCWrapper *)client->clientData;
    
    if (!wrapper) {
        NSLog(@"❌ VNC: Password callback - wrapper is NULL");
        return strdup("");
    }
    
    
    // First try to get password from saved password
    NSString *password = wrapper.savedPassword;
    
    // If no saved password, ask delegate
    if (!password || password.length == 0) {
        password = [wrapper.delegate vncPasswordForAuthentication];
    }
    
    // If still no password or empty password, notify that password is required
    if (!password || password.length == 0) {
        NSLog(@"🔐 VNC: No password available - notifying delegate");
        dispatch_async(dispatch_get_main_queue(), ^{
            [wrapper.delegate vncRequiresPassword];
        });
        // Return empty string to fail the authentication
        return strdup("");
    }
    
    NSLog(@"🔐 VNC: Password callback - password length: %lu", (unsigned long)password.length);
    NSLog(@"🔐 VNC: Password callback - returning password for authentication");
    
    char *result = strdup([password UTF8String]);
    if (!result) {
        NSLog(@"❌ VNC: Password callback - strdup failed");
        return strdup("");
    }
    
    return result;
}

static rfbBool resizeCallback(rfbClient* client) {
    LibVNCWrapper *wrapper = (__bridge LibVNCWrapper *)client->clientData;
    
    // Update screen size
    wrapper.screenSize = CGSizeMake(client->width, client->height);
    
    // Allocate framebuffer
    client->frameBuffer = malloc(client->width * client->height * 4);
    if (!client->frameBuffer) {
        return FALSE;
    }
    
    // Notify delegate of resize
    dispatch_async(dispatch_get_main_queue(), ^{
        [wrapper.delegate vncDidResize:wrapper.screenSize];
    });
    
    return TRUE;
}