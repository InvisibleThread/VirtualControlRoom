# Project Brief: Virtual Control Room (AVP Application)

## 1. Project Title
Virtual Control Room

## 2. Objective
To develop an Apple Vision Pro (AVP) application that enables users to securely access and control multiple remote computers via VNC, displayed as augmented reality windows. This application will streamline remote operations for users in environments like the Lawrence Berkeley Lab's Advanced Light Source (ALS) control room.

## 3. User Story

**User:** Thorsten, an ALS operator.

**Scenario:** Thorsten is at his home when he receives an urgent call requiring him to check the status of several systems at the Advanced Light Source.

1.  **Launch & Select:** Thorsten puts on his Apple Vision Pro and launches the "Virtual Control Room" application. He is presented with a list of pre-configured remote desktops relevant to his work. He selects the specific displays he needs to monitor and interact with.
2.  **Connect:** The application begins establishing secure connections for each selected display. It prompts Thorsten for his bastion server password and the current one-time code (OTP) from his authenticator app. He enters these credentials once.
3.  **Immersive Workspace:** As each connection is established, the remote desktops appear as floating augmented reality windows in front of Thorsten. The layout of these windows defaults to a configuration he saved during a previous session, creating an instant, familiar multi-monitor setup.
4.  **Interact & Diagnose:** Using his Bluetooth mouse and keyboard, already paired with his AVP, Thorsten seamlessly moves his cursor between the different remote desktop windows. He interacts with the various control systems, checks logs, and diagnoses the issue as if he were physically in the control room.
5.  **Resolve & Disconnect:** After addressing the situation, Thorsten closes each remote display window. The "Virtual Control Room" application then automatically terminates the corresponding VNC connections and, crucially, closes the underlying SSH tunnels, ensuring the connections to the ALS are secure.

## 4. Target Platform
Apple Vision Pro (visionOS)

## 5. Key Features

### Remote Desktop Access
* Connect to remote computers using VNC (Virtual Network Computing).
* Display each remote desktop as a resizable and movable augmented reality window within the user's AVP environment.

### Multi-Desktop Support
* Allow users to establish and manage multiple simultaneous VNC connections to different remote computers.
* Each connection will appear as a separate AR window.
* Support for saving and loading display window layouts.

### Native AVP Interaction
* Enable control of remote computers using AVP's native Bluetooth mouse and keyboard support.

### Secure Connectivity via SSH Bastion
* All VNC connections must be routed through an SSH bastion host before reaching the internal VNC servers.
* The application must establish and maintain these SSH tunnels automatically.

### User-Friendly Authentication
* **SSH Bastion Authentication:**
    * Requires username, password, and a one-time code (OTP) from an authenticator app.
    * The application should provide a secure and user-friendly way to manage the username and password (static part) and input the OTP. Aim to minimize re-entry for multiple connections within the same session if they use the same bastion credentials.
* **Internal VNC Server Authentication:**
    * Requires a separate set of username and password for each VNC server.
    * The application should allow secure storage and easy recall of these credentials per connection.

### Connection Management
* Allow users to configure, save, and manage connection profiles for different remote desktops (including bastion details, VNC server details, and credentials).
* Clear indication of connection status for each display.
* Graceful termination of connections and SSH tunnels when displays are closed or the application quits.

## 6. Technical Requirements & Considerations

### Connectivity & SSH Tunneling
* The application must internally manage the creation of SSH tunnels. For example, a connection might be established using a command similar to:
    ```bash
    ssh <bastion_user>@access-ctrl1.als.lbl.gov -fnNT -L <local_port>:<internal_vnc_host>:<internal_vnc_port>
    ```
* The application needs to dynamically assign and manage unique `local_port` numbers for each concurrent VNC session to avoid conflicts.
* Robust error handling and status reporting for SSH connection establishment (e.g., incorrect credentials, host unreachable, OTP failure).
* Ensure SSH tunnels are reliably closed when no longer needed.

### Authentication & Security
* **Bastion SSH Credentials:**
    * **Username/Password:** Securely store the bastion username and the static portion of the password (e.g., using Apple's Keychain services).
    * **OTP Input:** Provide a clear and simple interface for the user to input the OTP during the connection process. Avoid requiring copy-pasting if possible, though a text input field will likely be necessary.
* **Internal VNC Credentials:**
    * Securely store usernames and passwords for internal VNC servers (e.g., using Keychain services), associated with specific connection profiles.
    * Auto-fill or provide easy selection of these credentials when initiating a VNC connection.

### VNC Integration
* Integrate a VNC client library compatible with Swift and visionOS.
* The VNC client will connect to `localhost:<local_port>` established by the SSH tunnel. For example, based on the prototype:
    ```bash
    vncviewer UserName=<vnc_user> localhost:<local_port>
    ```
* Ensure efficient rendering of the VNC stream into an AR window.
* Handle various VNC encodings and screen resolutions.

### User Interface (UI) & User Experience (UX) for AVP
* Intuitive interface for adding, configuring, and launching remote desktop connections.
* Seamless management of multiple AR windows (remote desktops), including saving and loading layouts.
* Clear visual feedback for connection status (connecting, connected, disconnected, error).
* Easy access to keyboard and mouse input for interacting with the remote desktops.
* Minimize friction in the authentication process.

### Multi-Desktop Management
* The application must maintain multiple SSH tunnels and VNC client instances concurrently.
* Ensure stability and performance when multiple sessions are active.

## 7. Development Framework
* The application should be developed using **Apple's native Swift APIs** for visionOS to ensure optimal performance, integration, and user experience on the Apple Vision Pro.

## 8. Prototype Reference
A successful prototype was created using a bash script on a laptop. This script performed the following steps:
1.  Established a background SSH bastion connection:
    ```bash
    ssh ahessler@access-ctrl1.als.lbl.gov -fnNT -L 5920:appsdev2.als.lbl.gov:5980 2> /dev/null
    ```
    *(This maps local port 5920 to appsdev2.als.lbl.gov's port 5980 via the bastion)*
2.  Launched a VNC client connecting to the local port:
    ```bash
    vncviewer UserName=ahessler localhost:5920 2> /dev/null &
    ```
    *(The AVP application will need to replicate this tunneling and VNC client connection internally for each remote display.)*

## 9. Success Criteria
* Users can successfully and securely connect to one or more remote computers via VNC through the specified SSH bastion, following the workflow described in the User Story.
* The application provides a stable and responsive experience for interacting with multiple remote desktops in AR, including saved layouts.
* Authentication processes are secure yet user-friendly, minimizing redundant input.
* The application effectively utilizes native AVP features for input and display.
* SSH tunnels are reliably created and torn down with their respective VNC sessions.