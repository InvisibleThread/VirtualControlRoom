// Simplified connection method to replace the complex one

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
    
    // Store connection parameters safely
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
    
    // Handle result - but only if we haven't already reported an error
    if (!self.hasReportedError && !self.shouldCancelConnection) {
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