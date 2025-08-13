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
#import <string.h>

@interface LibVNCWrapper ()
@property (nonatomic, assign) rfbClient *client;
@property (nonatomic, strong) dispatch_queue_t vncQueue;
@property (nonatomic, strong) dispatch_queue_t inputQueue; // Separate queue for input events
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

// Static reference for password callback during authentication (when clientData is NULL)
static LibVNCWrapper *currentConnectionWrapper = nil;

// Static variables for capturing LibVNC error messages
static NSMutableString *lastLibVNCError = nil;
static NSMutableString *lastLibVNCLog = nil;
static int lastErrno = 0;

// Custom LibVNC logging callbacks to capture error details
static void customRfbClientLog(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    char buffer[4096];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    // Store the log message
    @synchronized([LibVNCWrapper class]) {
        if (!lastLibVNCLog) {
            lastLibVNCLog = [[NSMutableString alloc] init];
        }
        [lastLibVNCLog setString:[NSString stringWithUTF8String:buffer]];
    }
    
    // Also output to console for debugging
    fprintf(stderr, "LibVNC: %s", buffer);
}

static void customRfbClientErr(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    char buffer[4096];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    // Store the error message
    @synchronized([LibVNCWrapper class]) {
        if (!lastLibVNCError) {
            lastLibVNCError = [[NSMutableString alloc] init];
        }
        [lastLibVNCError setString:[NSString stringWithUTF8String:buffer]];
    }
    
    // Also output to console for debugging
    fprintf(stderr, "LibVNC Error: %s", buffer);
}

@implementation LibVNCWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _vncQueue = dispatch_queue_create("com.virtualcontrolroom.vnc", DISPATCH_QUEUE_SERIAL);
        _inputQueue = dispatch_queue_create("com.virtualcontrolroom.vnc.input", DISPATCH_QUEUE_SERIAL);
        _isConnected = NO;
        _screenSize = CGSizeZero;
        _framebufferUpdateCount = 0;
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
    
    // Keep local copies for use in blocks
    __weak typeof(self) weakSelf = self;
    NSString *hostCopy = [host copy];
    NSInteger portCopy = port;
    
    // Create a flag to track if we've already handled the result
    __block BOOL resultHandled = NO;
    
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
    
    /* 
     * CRITICAL LIBVNC CRASH FIX - December 13, 2024
     * ===============================================
     * 
     * PROBLEM: EXC_BAD_ACCESS crashes when rfbInitClient() fails on invalid hosts
     * 
     * ROOT CAUSE:
     * 1. When rfbInitClient() fails (e.g., invalid host, connection refused), it internally calls rfbClientCleanup()
     * 2. rfbClientCleanup() triggers callbacks (MallocFrameBuffer, GotFrameBufferUpdate, etc.) during cleanup
     * 3. These callbacks access client->clientData (which points to 'self') AFTER self might be deallocated
     * 4. Result: EXC_BAD_ACCESS crash when callbacks try to access freed memory
     * 
     * SOLUTION:
     * - Set client->clientData = NULL initially (no callbacks can access self)
     * - Only set callbacks and clientData AFTER rfbInitClient() succeeds
     * - Use captured delegate/timer references for error reporting to avoid accessing potentially freed self
     * 
     * REFERENCES:
     * - LibVNC Issue #205: rfbClientCleanup() crashes at free(client->serverHost)
     * - LibVNC Issue #47: crash at function rfbClientCleanup
     * - This fix prevents double-cleanup and callback-during-cleanup crashes
     */
    client->clientData = NULL;  // Start with NULL to prevent callback crashes during rfbInitClient failure
    
    self.savedPassword = password;
    
    // EXCEPTION: We need the password callback during rfbInitClient for authentication
    // This is safe because passwordCallback has NULL checks for clientData
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
    
    
    // The critical section - call rfbInitClient
    int argc = 0;
    char **argv = NULL;
    
    // CRITICAL: Before calling rfbInitClient, prepare for potential failure
    // We must assume that after this call, 'self' might be invalid
    
    // Capture everything we need BEFORE the call
    id<LibVNCWrapperDelegate> delegateCopy = self.delegate;
    NSTimer *timerCopy = self.connectionTimeoutTimer;
    
    // Mark that we're about to call rfbInitClient
    @synchronized(self) {
        resultHandled = YES;
    }
    
    // Set static reference for password callback (since clientData is NULL for safety)
    currentConnectionWrapper = self;
    
    // Clear previous error messages
    @synchronized([LibVNCWrapper class]) {
        [lastLibVNCError setString:@""];
        [lastLibVNCLog setString:@""];
        lastErrno = 0;
    }
    
    // Set custom logging callbacks to capture LibVNC errors
    extern rfbClientLogProc rfbClientLog;
    extern rfbClientLogProc rfbClientErr;
    rfbClientLogProc originalLog = rfbClientLog;
    rfbClientLogProc originalErr = rfbClientErr;
    rfbClientLog = customRfbClientLog;
    rfbClientErr = customRfbClientErr;
    
    // Call rfbInitClient WITHOUT most callbacks set - this prevents callback crashes on failure
    // NOTE: rfbInitClient will internally call rfbClientCleanup() if it fails, which would
    // trigger our callbacks if they were set, causing crashes when accessing freed clientData
    rfbBool initResult = rfbInitClient(client, &argc, argv);
    
    // Capture errno immediately after failure
    int capturedErrno = errno;
    
    // Capture LibVNC error messages
    NSString *capturedLibVNCError = nil;
    NSString *capturedLibVNCLog = nil;
    @synchronized([LibVNCWrapper class]) {
        if (lastLibVNCError && lastLibVNCError.length > 0) {
            capturedLibVNCError = [lastLibVNCError copy];
        }
        if (lastLibVNCLog && lastLibVNCLog.length > 0) {
            capturedLibVNCLog = [lastLibVNCLog copy];
        }
    }
    
    // Restore original logging callbacks
    rfbClientLog = originalLog;
    rfbClientErr = originalErr;
    
    // Clear static reference immediately after rfbInitClient
    currentConnectionWrapper = nil;
    
    
    // IMPORTANT: If rfbInitClient returns FALSE, the client structure has been freed!
    // Additionally, 'self' might be invalid due to callbacks during cleanup
    
    if (!initResult) {
        // Connection failed - rfbInitClient has already freed the client
        
        // Since we didn't set clientData, we can safely access self
        self.selfReference = nil;
        
        NSString *errorMsg = [NSString stringWithFormat:@"Failed to connect to VNC server at %@:%ld", hostCopy, (long)portCopy];
        NSString *errnoString = capturedErrno ? [NSString stringWithUTF8String:strerror(capturedErrno)] : nil;
        
        // Report error using captured references (safer)
        dispatch_async(dispatch_get_main_queue(), ^{
            // Use captured timer reference
            [timerCopy invalidate];
            
            // Report error through captured delegate with detailed information
            if (delegateCopy) {
                if ([delegateCopy respondsToSelector:@selector(vncDidFailWithDetailedError:libVNCError:errnoValue:errnoString:)]) {
                    [delegateCopy vncDidFailWithDetailedError:errorMsg 
                                                  libVNCError:capturedLibVNCError ?: capturedLibVNCLog
                                                   errnoValue:capturedErrno
                                                 errnoString:errnoString];
                } else if ([delegateCopy respondsToSelector:@selector(vncDidFailWithError:)]) {
                    // Fallback to simple error for backward compatibility
                    [delegateCopy vncDidFailWithError:errorMsg];
                }
            }
        });
        
        return;
    }
    
    // Connection succeeded - check if we should proceed
    __block BOOL shouldProceed = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        shouldProceed = !strongSelf.hasReportedError && !strongSelf.shouldCancelConnection;
    });
    
    // Handle success - but only if we haven't already reported an error
    if (shouldProceed) {
        // NOW we can safely set up callbacks and clientData since rfbInitClient succeeded
        // This is the ONLY safe time to set these - after we know the connection worked
        client->clientData = (__bridge void *)self;
        client->MallocFrameBuffer = resizeCallback;
        client->GotFrameBufferUpdate = framebufferUpdateCallback;
        client->GetPassword = passwordCallback;
        
        // Request initial framebuffer update
        SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
        
        @synchronized(self) {
            self.client = client;
        }
        
        // Manually trigger resize since it happened during rfbInitClient before callbacks were set
        if (client->width > 0 && client->height > 0) {
            resizeCallback(client);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            // Cancel timeout timer
            [strongSelf.connectionTimeoutTimer invalidate];
            strongSelf.connectionTimeoutTimer = nil;
        });
        
        // Success
        self.isConnected = YES;
        self.selfReference = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            if (strongSelf.delegate && !strongSelf.hasReportedError) {
                [strongSelf.delegate vncDidConnect];
            }
        });
        
        // Start event loop
        [self runEventLoop];
    } else {
        // We already reported an error (timeout) - just cleanup
        NSLog(@"⚠️ VNC: Ignoring rfbInitClient result - already reported error");
        // Don't set self.client since we never stored it in the first place
        self.selfReference = nil;
    }
}

- (void)disconnect {
    NSLog(@"🔌 VNC: Manual disconnect requested");
    
    // Reset error state for clean disconnection
    self.hasReportedError = NO;
    
    // Use enhanced cleanup
    [self performCleanup];
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
    // Simple validation - match original working version
    if (!self.client || !self.isConnected) {
        return;
    }
    
    rfbClient *client = self.client;
    // Use separate input queue to avoid blocking with event loop
    dispatch_async(self.inputQueue, ^{
        SendKeyEvent(client, keysym, down ? TRUE : FALSE);
    });
}

- (void)sendPointerEvent:(NSInteger)x y:(NSInteger)y buttonMask:(NSInteger)mask {
    NSLog(@"📥 LibVNCWrapper: sendPointerEvent called with x:%ld y:%ld mask:%ld", (long)x, (long)y, (long)mask);
    
    // Simple validation - match original working version
    if (!self.client || !self.isConnected) {
        NSLog(@"⚠️ VNC: sendPointerEvent blocked - client:%p connected:%d", self.client, self.isConnected);
        return;
    }
    
    rfbClient *client = self.client;
    
    // Use separate input queue to avoid blocking with event loop
    dispatch_async(self.inputQueue, ^{
        NSLog(@"🎯 LibVNCWrapper: Inside input queue - about to call SendPointerEvent");
        SendPointerEvent(client, (int)x, (int)y, (int)mask);
        NSLog(@"✅ LibVNCWrapper: SendPointerEvent completed");
    });
}

#pragma mark - Internal Methods

- (void)handleFramebufferUpdate {
    // Increment counter and only log every 100th update to reduce spam
    self.framebufferUpdateCount++;
    if (self.framebufferUpdateCount % 100 == 0) {
        NSLog(@"🖼️ LibVNCWrapper: handleFramebufferUpdate called (update #%lu)", (unsigned long)self.framebufferUpdateCount);
    }
    
    // Enhanced safety checks
    if (!self.client) {
        NSLog(@"⚠️ Cannot handle framebuffer update - client is NULL");
        return;
    }
    
    if (!self.isConnected) {
        NSLog(@"⚠️ Cannot handle framebuffer update - not connected");
        return;
    }
    
    rfbClient *client = self.client;
    
    // Validate framebuffer data
    if (!client->frameBuffer) {
        NSLog(@"⚠️ Cannot handle framebuffer update - frameBuffer is NULL");
        return;
    }
    
    if (client->width <= 0 || client->height <= 0) {
        NSLog(@"⚠️ Cannot handle framebuffer update - invalid dimensions %dx%d", client->width, client->height);
        return;
    }
    
    // Check for reasonable dimensions to prevent crashes
    if (client->width > 8192 || client->height > 8192) {
        NSLog(@"⚠️ Cannot handle framebuffer update - dimensions too large %dx%d", client->width, client->height);
        return;
    }
    
    @try {
        // Create CGImage from framebuffer with safety checks
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (!colorSpace) {
            NSLog(@"❌ Failed to create color space");
            return;
        }
        
        size_t bufferSize = (size_t)client->width * (size_t)client->height * 4;
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, 
                                                                 client->frameBuffer, 
                                                                 bufferSize, 
                                                                 NULL);
        if (!provider) {
            NSLog(@"❌ Failed to create data provider");
            CGColorSpaceRelease(colorSpace);
            return;
        }
        
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
                if (self.delegate) {
                    [self.delegate vncDidUpdateFramebuffer:image];
                }
                CGImageRelease(image);
            });
        } else {
            NSLog(@"❌ Failed to create CGImage from framebuffer");
        }
        
    } @catch (NSException *exception) {
        NSLog(@"❌ VNC: handleFramebufferUpdate exception: %@", exception.reason);
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
        
        // Connection ended - perform cleanup
        [self performCleanup];
    });
}

- (void)reportErrorIfNeeded:(NSString *)error {
    if (!self.hasReportedError) {
        self.hasReportedError = YES;
        
        NSLog(@"❌ VNC: Reporting error: %@", error);
        
        // Enhanced error context
        NSString *enhancedError = error;
        if (!enhancedError || enhancedError.length == 0) {
            enhancedError = @"Unknown VNC connection error";
        }
        
        // Add connection context if available
        if (self.client) {
            NSString *context = [NSString stringWithFormat:@"%@ (Connection state: client=%p, connected=%d)", 
                               enhancedError, self.client, self.isConnected];
            enhancedError = context;
        }
        
        // Clean up connection state
        [self performCleanup];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate) {
                [self.delegate vncDidFailWithError:enhancedError];
            }
        });
    }
}

- (void)performCleanup {
    NSLog(@"🧹 VNC: Performing connection cleanup");
    
    // Early return if already cleaned up
    if (!self.vncQueue) {
        NSLog(@"⚠️ VNC: Already cleaned up - vncQueue is nil");
        return;
    }
    
    // Stop connection attempts first
    self.shouldCancelConnection = YES;
    self.isConnected = NO;
    
    // Cancel timeout timer if running
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
    
    // Clean up VNC client - synchronously to avoid race conditions
    if (self.client) {
        rfbClient *clientToCleanup = self.client;
        
        // Clear clientData first to prevent callbacks from accessing wrapper
        clientToCleanup->clientData = NULL;
        
        // Now clear our reference
        self.client = NULL;
        
        // Define cleanup block
        void (^cleanupBlock)(void) = ^{
            @try {
                if (clientToCleanup) {
                    // Free framebuffer if allocated
                    if (clientToCleanup->frameBuffer) {
                        free(clientToCleanup->frameBuffer);
                        clientToCleanup->frameBuffer = NULL;
                    }
                    
                    // Clean up client
                    rfbClientCleanup(clientToCleanup);
                }
            } @catch (NSException *exception) {
                NSLog(@"❌ VNC: Exception during client cleanup: %@", exception.reason);
            }
        };
        
        // Execute cleanup on vncQueue if it still exists
        // Use dispatch_async to avoid potential deadlock and ensure cleanup happens after any pending operations
        dispatch_queue_t queue = self.vncQueue;
        if (queue) {
            dispatch_async(queue, cleanupBlock);
        } else {
            NSLog(@"⚠️ VNC: vncQueue is nil, skipping async cleanup");
        }
    }
    
    // Notify delegate about disconnection
    // Capture delegate before async dispatch to avoid accessing deallocated self
    id<LibVNCWrapperDelegate> delegateCopy = self.delegate;
    if (delegateCopy) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"🔔 VNC: Notifying delegate about disconnection");
            [delegateCopy vncDidDisconnect];
        });
    }
    
    // Clear self reference LAST to allow proper deallocation
    self.selfReference = nil;
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
    // Critical safety checks to prevent crashes
    if (!client) {
        NSLog(@"❌ VNC: framebufferUpdateCallback - client is NULL");
        return;
    }
    
    if (!client->clientData) {
        NSLog(@"❌ VNC: framebufferUpdateCallback - clientData is NULL");
        return;
    }
    
    LibVNCWrapper *wrapper = (__bridge LibVNCWrapper *)client->clientData;
    if (!wrapper) {
        NSLog(@"❌ VNC: framebufferUpdateCallback - wrapper is NULL");
        return;
    }
    
    // Check if wrapper is still valid (not deallocated)
    @try {
        [wrapper handleFramebufferUpdate];
        
        // Only request next update if client is still valid
        if (client && client->width > 0 && client->height > 0) {
            SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, TRUE);
        }
    } @catch (NSException *exception) {
        NSLog(@"❌ VNC: framebufferUpdateCallback exception: %@", exception.reason);
    }
}

static char* passwordCallback(rfbClient* client) {
    NSLog(@"🔐 VNC: Password callback called");
    
    // Critical safety checks
    if (!client) {
        NSLog(@"❌ VNC: passwordCallback - client is NULL");
        return strdup("");
    }
    
    LibVNCWrapper *wrapper = nil;
    
    if (client->clientData) {
        wrapper = (__bridge LibVNCWrapper *)client->clientData;
    } else {
        // During initial authentication, clientData is NULL for safety
        // Use static reference instead
        NSLog(@"🔐 VNC: Using static reference for password (clientData is NULL for safety)");
        wrapper = currentConnectionWrapper;
    }
    
    if (!wrapper) {
        NSLog(@"❌ VNC: Password callback - no wrapper available");
        return strdup("");
    }
    
    
    // First try to get password from saved password
    NSString *password = wrapper.savedPassword;
    NSLog(@"🔐 VNC: Password callback - wrapper.savedPassword = %@", password ? @"[PASSWORD_FOUND]" : @"[NIL]");
    
    // If no saved password, ask delegate
    if (!password || password.length == 0) {
        password = [wrapper.delegate vncPasswordForAuthentication];
        NSLog(@"🔐 VNC: Password callback - delegate returned = %@", password ? @"[PASSWORD_FOUND]" : @"[NIL]");
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
    // Critical safety checks
    if (!client) {
        NSLog(@"❌ VNC: resizeCallback - client is NULL");
        return FALSE;
    }
    
    if (!client->clientData) {
        NSLog(@"❌ VNC: resizeCallback - clientData is NULL");
        return FALSE;
    }
    
    if (client->width <= 0 || client->height <= 0) {
        NSLog(@"❌ VNC: resizeCallback - invalid dimensions %dx%d", client->width, client->height);
        return FALSE;
    }
    
    // Check for reasonable size limits to prevent memory exhaustion
    if (client->width > 8192 || client->height > 8192) {
        NSLog(@"❌ VNC: resizeCallback - dimensions too large %dx%d (max 8192x8192)", client->width, client->height);
        return FALSE;
    }
    
    LibVNCWrapper *wrapper = (__bridge LibVNCWrapper *)client->clientData;
    if (!wrapper) {
        NSLog(@"❌ VNC: resizeCallback - wrapper is NULL");
        return FALSE;
    }
    
    @try {
        // Free existing framebuffer if any
        if (client->frameBuffer) {
            free(client->frameBuffer);
            client->frameBuffer = NULL;
        }
        
        // Calculate required memory size and check for overflow
        size_t bufferSize = (size_t)client->width * (size_t)client->height * 4;
        if (bufferSize < client->width || bufferSize < client->height) {
            NSLog(@"❌ VNC: resizeCallback - buffer size overflow");
            return FALSE;
        }
        
        // Allocate framebuffer with size checking
        client->frameBuffer = malloc(bufferSize);
        if (!client->frameBuffer) {
            NSLog(@"❌ VNC: resizeCallback - malloc failed for %dx%d buffer", client->width, client->height);
            return FALSE;
        }
        
        // Update screen size
        wrapper.screenSize = CGSizeMake(client->width, client->height);
        
        // Notify delegate of resize
        dispatch_async(dispatch_get_main_queue(), ^{
            if (wrapper.delegate) {
                [wrapper.delegate vncDidResize:wrapper.screenSize];
            }
        });
        
        NSLog(@"✅ VNC: resizeCallback - successfully resized to %dx%d", client->width, client->height);
        return TRUE;
        
    } @catch (NSException *exception) {
        NSLog(@"❌ VNC: resizeCallback exception: %@", exception.reason);
        if (client->frameBuffer) {
            free(client->frameBuffer);
            client->frameBuffer = NULL;
        }
        return FALSE;
    }
}