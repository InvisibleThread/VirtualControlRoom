# Setting Up LibVNCClient

This guide explains how to configure LibVNCClient in the VirtualControlRoom project.

## Background

We migrated from RoyalVNCKit to LibVNCClient because RoyalVNCKit's `cgImage` property was returning `nil` with certain VNC servers (particularly TightVNC on Windows). LibVNCClient provides direct access to framebuffer data and better compatibility across all VNC server types.

## Prerequisites

1. **Install LibVNCClient via Homebrew**:
   ```bash
   brew install libvnc
   ```

## Xcode Configuration Steps

### 1. Configure Build Settings

In Xcode, select your project and go to the target's Build Settings:

#### Header Search Paths
Add the following paths (non-recursive):
- **Apple Silicon Macs**: `/opt/homebrew/include`
- **Intel Macs**: `/usr/local/include`

#### Library Search Paths
Add the following paths (non-recursive):
- **Apple Silicon Macs**: `/opt/homebrew/lib`
- **Intel Macs**: `/usr/local/lib`

#### Other Linker Flags
Add: `-lvncclient`

#### Objective-C Bridging Header
Set to: `VirtualControlRoom/VirtualControlRoom-Bridging-Header.h`

### 2. Add Files to Project

The following files should already be in the project:
- `Services/VNC/LibVNCWrapper.h` - Objective-C header
- `Services/VNC/LibVNCWrapper.m` - Objective-C implementation
- `Services/VNC/LibVNCClient.swift` - Swift wrapper
- `VirtualControlRoom-Bridging-Header.h` - Bridging header

Make sure all these files are included in the target membership.

### 3. Remove RoyalVNCKit References

If you haven't already:
1. Remove RoyalVNCKit from Package Dependencies
2. Remove any `import RoyalVNCKit` statements
3. The file `RoyalVNCClient.swift.bak` is kept as reference but excluded from build

## Architecture Overview

```
LibVNCClient.swift (Swift)
    ↓ delegates to
LibVNCWrapper (Objective-C)
    ↓ wraps
libvncclient (C library)
```

### Key Components:

1. **LibVNCClient.swift**: 
   - Conforms to `VNCClient` protocol
   - Same API as RoyalVNCClient for drop-in replacement
   - Handles image scaling and SwiftUI integration

2. **LibVNCWrapper.h/m**:
   - Objective-C wrapper around C library
   - Manages VNC connection lifecycle
   - Converts framebuffer to CGImage

3. **Bridging Header**:
   - Exposes Objective-C code to Swift
   - Contains: `#import "Services/VNC/LibVNCWrapper.h"`

## Testing

After configuration:
1. Build the project (⌘B)
2. Run the app
3. Test with both:
   - macOS Screen Sharing (port 5900)
   - TightVNC on Windows (port 5900)

## Troubleshooting

### Build Errors

1. **"rfb/rfbclient.h not found"**:
   - Verify libvnc is installed: `brew list libvnc`
   - Check header search paths are correct
   - Try: `brew reinstall libvnc`

2. **Linker errors (undefined symbols)**:
   - Verify library search paths
   - Check that `-lvncclient` is in Other Linker Flags

3. **Module not found errors**:
   - Verify bridging header path is correct
   - Clean build folder (⌘⇧K) and rebuild

### Runtime Issues

1. **Connection failures**:
   - Check VNC server is running
   - Verify port is correct (usually 5900)
   - Check firewall settings

2. **Black screen**:
   - This indicates connection works but framebuffer conversion failed
   - Check console logs for specific errors

## Performance Notes

- LibVNCClient handles large displays better than RoyalVNCKit
- Automatic scaling for displays > 4K resolution
- Framebuffer updates run on background queue

## Future Enhancements

- [ ] Add support for more VNC encodings
- [ ] Implement clipboard synchronization
- [ ] Add support for VNC authentication methods beyond password