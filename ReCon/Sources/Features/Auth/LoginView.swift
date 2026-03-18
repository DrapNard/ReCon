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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("ReCon")
                        .font(.largeTitle.bold())

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
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
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
