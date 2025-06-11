//
//  LibVNCWrapper.m
//  VirtualControlRoom
//
//  Objective-C wrapper for LibVNCClient C library
//

#import "LibVNCWrapper.h"
#import <rfb/rfbclient.h>

@interface LibVNCWrapper ()
@property (nonatomic, assign) rfbClient *client;
@property (nonatomic, strong) dispatch_queue_t vncQueue;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) CGSize screenSize;
@property (nonatomic, strong) NSString *savedPassword;
@property (nonatomic, strong) NSThread *vncThread;
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
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.vncQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            NSLog(@"❌ VNC: strongSelf is nil in connection block");
            return;
        }
        
        NSLog(@"🔄 VNC: Starting connection process in background queue");
        
        // Perform LibVNC library initialization checks
        NSLog(@"🔧 VNC: Checking LibVNC library availability...");
        
        // Create VNC client structure with safer parameters
        NSLog(@"🔧 VNC: Calling rfbGetClient(8, 3, 4)...");
        rfbClient *client = rfbGetClient(8, 3, 4); // 8 bits per sample, 3 samples per pixel, 4 bytes per pixel
        
        if (!client) {
            NSLog(@"❌ VNC: rfbGetClient failed - could not allocate client structure");
            NSLog(@"❌ VNC: This suggests LibVNC library may not be properly linked or initialized");
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Failed to create VNC client - library error"];
            });
            return;
        }
        
        NSLog(@"✅ VNC: Successfully created client structure at %p", client);
        
        // Store reference for callbacks
        NSLog(@"🔄 VNC: Setting up client data and callbacks");
        client->clientData = (__bridge void *)strongSelf;
        strongSelf.client = client;
        strongSelf.savedPassword = password;
        
        // Set up callbacks with validation
        if (client) {
            client->MallocFrameBuffer = resizeCallback;
            client->GotFrameBufferUpdate = framebufferUpdateCallback;
            client->GetPassword = passwordCallback;
            NSLog(@"✅ VNC: Callbacks configured successfully");
        } else {
            NSLog(@"❌ VNC: Client is NULL, cannot set callbacks");
            return;
        }
        
        // Enable common encodings
        client->appData.encodingsString = "copyrect hextile raw";
        client->appData.compressLevel = 9;
        client->appData.qualityLevel = 9;
        
        // Configure connection with validation
        if (!host || host.length == 0) {
            NSLog(@"❌ VNC: Invalid host parameter");
            rfbClientCleanup(client);
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Invalid host parameter"];
            });
            return;
        }
        
        if (port <= 0 || port > 65535) {
            NSLog(@"❌ VNC: Invalid port parameter: %ld", (long)port);
            rfbClientCleanup(client);
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Invalid port parameter"];
            });
            return;
        }
        
        NSLog(@"🔄 VNC: Setting server host and port");
        char *hostCString = strdup([host UTF8String]);
        if (hostCString) {
            client->serverHost = hostCString;
            NSLog(@"✅ VNC: Server host set to: %s", client->serverHost);
        } else {
            NSLog(@"❌ VNC: Failed to allocate memory for server host");
            rfbClientCleanup(client);
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Memory allocation failed for host"];
            });
            return;
        }
        
        client->serverPort = (int)port;
        NSLog(@"✅ VNC: Server port set to: %d", client->serverPort);
        
        // Set pixel format for best compatibility
        NSLog(@"🔄 VNC: Setting pixel format");
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
        NSLog(@"✅ VNC: Pixel format configured: %dx%d, %d bpp", client->width, client->height, client->format.bitsPerPixel);
        
        // Initialize and connect with better error handling
        NSLog(@"🔄 VNC: Attempting to connect to %@:%d", host, (int)port);
        NSLog(@"🔍 VNC: Pre-connection client state - client:%p, serverHost:%s, serverPort:%d", 
              client, client->serverHost ? client->serverHost : "NULL", client->serverPort);
        
        // Additional safety checks before calling rfbInitClient
        if (!client) {
            NSLog(@"❌ VNC: Client is NULL before rfbInitClient call");
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Internal error: client is NULL"];
            });
            return;
        }
        
        if (!client->serverHost) {
            NSLog(@"❌ VNC: serverHost is NULL before rfbInitClient call");
            rfbClientCleanup(client);
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Internal error: serverHost is NULL"];
            });
            return;
        }
        
        NSLog(@"🚀 VNC: Calling rfbInitClient...");
        // Provide dummy argc/argv to prevent potential crashes from NULL parameters
        int argc = 0;
        char **argv = NULL;
        rfbBool initResult = rfbInitClient(client, &argc, argv);
        NSLog(@"🔍 VNC: rfbInitClient returned: %s", initResult ? "TRUE" : "FALSE");
        
        if (!initResult) {
            NSLog(@"❌ VNC: rfbInitClient failed for %@:%d", host, (int)port);
            strongSelf.client = NULL;
            
            // Clean up client resources
            if (client->serverHost) {
                free(client->serverHost);
                client->serverHost = NULL;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *errorMsg = [NSString stringWithFormat:@"Failed to connect to VNC server at %@:%d", host, (int)port];
                [strongSelf.delegate vncDidFailWithError:errorMsg];
            });
            return;
        }
        
        strongSelf.isConnected = YES;
        
        // Request initial framebuffer update
        if (client->width > 0 && client->height > 0) {
            SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
            NSLog(@"📺 Requested initial framebuffer update for %dx%d", client->width, client->height);
        } else {
            NSLog(@"⚠️ Cannot request framebuffer update - invalid dimensions: %dx%d", client->width, client->height);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.delegate vncDidConnect];
        });
        
        // Main VNC event loop
        while (strongSelf.isConnected && client) {
            int result = WaitForMessage(client, 100000); // 100ms timeout
            if (result > 0) {
                if (!HandleRFBServerMessage(client)) {
                    NSLog(@"❌ HandleRFBServerMessage failed");
                    break;
                }
            } else if (result < 0) {
                NSLog(@"❌ WaitForMessage error: %d", result);
                break;
            }
            // Process any pending events
            else if (result == 0) {
                // Timeout - this is normal, continue loop
            }
        }
        
        // Cleanup on disconnect
        strongSelf.isConnected = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.delegate vncDidDisconnect];
        });
    });
    
    return YES;
}

- (void)disconnect {
    self.isConnected = NO;
    
    if (self.client) {
        rfbClient *client = self.client;
        self.client = NULL;
        
        dispatch_async(self.vncQueue, ^{
            rfbClientCleanup(client);
        });
    }
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

@end

#pragma mark - C Callbacks

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

static void logCallback(const char *format, ...) {
    // Suppress verbose LibVNCClient logging
}