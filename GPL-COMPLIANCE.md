# GPL Compliance Notice

## Virtual Control Room - GPL Compliance Information

**Important**: This application includes GPL v2 licensed components, which affects the licensing of the entire work.

### GPL v2 Components Included

**LibVNC (LibVNCServer/LibVNCClient)**
- Location: `VirtualControlRoom/build-libs/libvncserver/`
- License: GNU General Public License version 2
- Copyright: LibVNC Project Contributors
- Purpose: VNC protocol implementation for remote desktop connectivity

### Your Rights Under GPL v2

As a recipient of this software, you have the following rights under GPL v2:

1. **Use**: You may use this software for any purpose
2. **Study**: You may examine how the software works
3. **Modify**: You may modify the software to suit your needs
4. **Distribute**: You may distribute the software to others
5. **Share Improvements**: You may distribute your modifications

### GPL v2 Obligations

If you distribute this software (modified or unmodified), you must:

1. **Provide Source Code**: Make complete source code available to recipients
2. **Include License**: Provide a copy of the GPL v2 license
3. **Preserve Notices**: Keep all copyright and license notices intact
4. **No Additional Restrictions**: Cannot impose additional terms or restrictions
5. **Same License**: Any derivative works must be licensed under GPL v2

### Source Code Availability

Complete source code for Virtual Control Room is available at:
- **Repository**: [Your repository URL will go here]
- **Version**: 0.70
- **Branch**: main

This includes:
- All Virtual Control Room source code
- Build scripts and configuration files
- LibVNC source code (in build-libs/libvncserver/)
- Dependencies managed by Swift Package Manager

### How to Obtain Source Code

The source code is provided in the following ways:

1. **Git Repository**: Clone the complete repository
   ```bash
   git clone [repository-url]
   cd VirtualControlRoom
   ```

2. **Source Archive**: Download complete source as ZIP archive
   - Available from the repository's releases page
   - Includes all dependencies and build tools

### Building from Source

To build Virtual Control Room from source:

1. **Requirements**:
   - macOS 15.0 (Sequoia) or later
   - Xcode 16.0 or later
   - Apple Vision Pro for device testing

2. **Build Instructions**:
   ```bash
   open VirtualControlRoom/VirtualControlRoom.xcodeproj
   # Select scheme and build target in Xcode
   # Press Cmd+B to build
   ```

3. **Dependencies**: All dependencies are included or automatically downloaded

### LibVNC Specific Information

LibVNC is distributed under GPL v2 terms:

- **Version**: As included in build-libs/libvncserver/
- **Modifications**: [List any modifications made to LibVNC]
- **Original Source**: https://github.com/LibVNC/libvncserver
- **License File**: `VirtualControlRoom/build-libs/libvncserver/COPYING`

### No Warranty

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

### GPL v2 License Text

The complete GNU General Public License version 2 is available at:
- **Local Copy**: `VirtualControlRoom/build-libs/libvncserver/COPYING`
- **Online**: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

### Contact Information

For questions about GPL compliance or source code availability:
- **Project**: Virtual Control Room
- **Version**: 0.70
- **Contact**: [Your contact information]

### Alternative Licensing

The Virtual Control Room source code (excluding LibVNC) is also available under BSD 3-Clause License. However, any distribution that includes LibVNC must comply with GPL v2 terms.

For a purely BSD-licensed version, LibVNC would need to be replaced with a compatible alternative.

---

**This notice satisfies GPL v2 Section 1 and Section 3 requirements for source code availability and license notification.**

Last updated: January 8, 2025