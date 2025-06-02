# Setting Up RoyalVNCKit

To test real VNC connections, you need to add RoyalVNCKit to the project:

## Steps to Add RoyalVNCKit

1. **Open the project in Xcode**

2. **Add Package Dependency**:
   - Go to `File` → `Add Package Dependencies...`
   - In the search field, enter: `https://github.com/royalapplications/royalvnc.git`
   - Click `Add Package`
   - Select `RoyalVNCKit` library
   - Add to `VirtualControlRoom` target
   - Click `Add Package`

3. **Enable RoyalVNCKit in Code**:
   - Open `RoyalVNCClient.swift`
   - Uncomment the `import RoyalVNCKit` line at the top
   - The placeholder code will guide you through implementation

## Testing with Your VNC Server

Once RoyalVNCKit is added:

1. Run the app
2. Click "VNC Test"
3. Enter your VNC server details:
   - Host: Your VNC server IP/hostname
   - Port: Usually 5900
   - Username: Your VNC username (if required)
   - Password: Your VNC password
4. Click "Connect"
5. If successful, click "Show in AR" to see the desktop in spatial view

## Troubleshooting

- If the package fails to resolve, try:
  - Clean build folder (Cmd+Shift+K)
  - Reset package caches: File → Packages → Reset Package Caches
  - Restart Xcode

- RoyalVNCKit requires:
  - visionOS 1.0+
  - Swift 5.9+

## Current Status

The app currently shows an error message because RoyalVNCKit is not yet integrated. Once you add the package, the real VNC implementation will be available.