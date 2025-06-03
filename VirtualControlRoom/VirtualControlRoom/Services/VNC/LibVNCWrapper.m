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
        if (!strongSelf) return;
        
        // Create VNC client structure
        rfbClient *client = rfbGetClient(8, 3, 4); // 8 bits per sample, 3 samples per pixel, 4 bytes per pixel
        if (!client) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Failed to create VNC client"];
            });
            return;
        }
        
        // Store reference for callbacks
        client->clientData = (__bridge void *)strongSelf;
        strongSelf.client = client;
        strongSelf.savedPassword = password;
        
        // Set up callbacks
        client->MallocFrameBuffer = resizeCallback;
        client->GotFrameBufferUpdate = framebufferUpdateCallback;
        client->GetPassword = passwordCallback;
        
        // Configure connection
        client->serverHost = strdup([host UTF8String]);
        client->serverPort = (int)port;
        
        // Set pixel format for best compatibility
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
        
        // Initialize and connect
        if (!rfbInitClient(client, NULL, NULL)) {
            strongSelf.client = NULL;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate vncDidFailWithError:@"Failed to connect to VNC server"];
            });
            return;
        }
        
        strongSelf.isConnected = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.delegate vncDidConnect];
        });
        
        // Main VNC event loop
        while (strongSelf.isConnected && client) {
            int result = WaitForMessage(client, 100000); // 100ms timeout
            if (result > 0) {
                if (!HandleRFBServerMessage(client)) {
                    break;
                }
            } else if (result < 0) {
                break;
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
    if (!self.client || !self.isConnected) return;
    
    rfbClient *client = self.client;
    dispatch_async(self.vncQueue, ^{
        SendKeyEvent(client, keysym, down ? TRUE : FALSE);
    });
}

- (void)sendPointerEvent:(NSInteger)x y:(NSInteger)y buttonMask:(NSInteger)mask {
    if (!self.client || !self.isConnected) return;
    
    rfbClient *client = self.client;
    dispatch_async(self.vncQueue, ^{
        SendPointerEvent(client, (int)x, (int)y, (int)mask);
    });
}

#pragma mark - Internal Methods

- (void)handleFramebufferUpdate {
    if (!self.client || !self.isConnected) return;
    
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
}

static char* passwordCallback(rfbClient* client) {
    LibVNCWrapper *wrapper = (__bridge LibVNCWrapper *)client->clientData;
    NSString *password = wrapper.savedPassword ?: @"";
    return strdup([password UTF8String]);
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