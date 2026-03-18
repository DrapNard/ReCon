import SwiftUI

struct LoginView: View {
    @ObservedObject var app: AppContainer

    private enum Field: Hashable {
        case username
        case password
        case totp
    }

    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var needsTotp = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, 20)
            let bottomInset = max(geo.safeAreaInsets.bottom, 20)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.09, blue: 0.20),
                                Color(red: 0.07, green: 0.15, blue: 0.30),
                                Color(red: 0.11, green: 0.22, blue: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("ReCon")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.84), Color.accentColor.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("SIGN IN")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        TextField("Username or email", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .username)
                            .onSubmit { focusedField = .password }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        Divider()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(needsTotp ? .next : .go)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                if needsTotp {
                                    focusedField = .totp
                                } else {
                                    Task { await submit() }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        if needsTotp {
                            Divider()
                            TextField("2FA Code", text: $totp)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focusedField, equals: .totp)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Login")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || username.isEmpty || password.isEmpty || (needsTotp && totp.isEmpty))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, topInset + 20)
                .padding(.bottom, bottomInset + 24)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func submit() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            try await app.login(username: username, password: password, totp: needsTotp ? totp : nil)
        } catch let error as AppError {
            switch error {
            case .totpRequired:
                needsTotp = true
                errorMessage = "Please enter your 2FA-Code"
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
