import SwiftUI

struct OTPPromptView: View {
    @Binding var isPresented: Bool
    let connectionName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    
    @State private var otpCode = ""
    @FocusState private var isOTPFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon and title
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
                
                Text("One-Time Passcode Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter OTP for SSH connection to")
                    .foregroundStyle(.secondary)
                Text(connectionName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // OTP input field
            VStack(alignment: .leading, spacing: 8) {
                Text("One-Time Passcode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("Enter OTP", text: $otpCode)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.system(.title3, design: .monospaced))
                    .focused($isOTPFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if !otpCode.isEmpty {
                            submitOTP()
                        }
                    }
            }
            .padding(.horizontal)
            
            // Buttons
            HStack(spacing: 15) {
                Button("Cancel") {
                    onCancel()
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Connect") {
                    print("🔘 OTP Connect button tapped")
                    submitOTP()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(otpCode.isEmpty)
            }
            
            // Info text
            Text("This code will be appended to your SSH password")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(width: 400)
        .onAppear {
            // Focus the OTP field immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isOTPFieldFocused = true
            }
        }
    }
    
    private func submitOTP() {
        guard !otpCode.isEmpty else { 
            print("❌ OTP submission blocked: empty OTP code")
            return 
        }
        print("✅ OTP submitted: \(otpCode.count) characters")
        onSubmit(otpCode)
        isPresented = false
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
        
        OTPPromptView(
            isPresented: .constant(true),
            connectionName: "access-ctrl1.als.lbl.gov",
            onSubmit: { otp in
                print("OTP submitted: \(otp)")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
}