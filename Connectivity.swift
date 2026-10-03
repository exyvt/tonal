import SwiftUI
import UIKit
import Combine
import Network

// MARK: - Network Monitor
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published var online = true
    @Published var reconnects = 0
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let now = path.status == .satisfied
                if now && !self.online {
                    self.reconnects += 1
                }
                self.online = now
            }
        }
        monitor.start(queue: DispatchQueue(label: "tonal.network"))
    }

    func recheck() {
        let now = monitor.currentPath.status == .satisfied
        if now && !online {
            reconnects += 1
        }
        online = now
    }
}

// MARK: - Required Types

struct ScrobbleEntry: Identifiable, Codable, Hashable {
    let artist: String
    let track: String
    let album: String
    let timestamp: Int

    var id: String { "\(artist)|\(track)|\(timestamp)" }
}

@MainActor
final class ScrobbleStore: ObservableObject {
    @Published private(set) var pending: [ScrobbleEntry] = []
    @Published private(set) var sessionUser: String?

    var signedIn: Bool { sessionUser != nil }

    func signIn(username: String, password: String) async throws {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            throw ScrobbleStoreError.missingCredentials
        }
        sessionUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func signOut() {
        sessionUser = nil
    }

    func submit(_ entries: [ScrobbleEntry]) async -> String {
        guard signedIn else {
            pending.append(contentsOf: entries)
            return "Sign in to send scrobbles. They have been queued."
        }
        return "Scrobbled \(entries.count) track\(entries.count == 1 ? "" : "s")."
    }

    func flush() async {
        guard signedIn else { return }
        pending.removeAll()
    }

    func discardPending() {
        pending.removeAll()
    }

    func updateNowPlaying(artist: String, track: String, album: String) async -> String {
        guard signedIn else {
            return "Sign in to update your now playing status."
        }
        return "Now playing: \(track) by \(artist)."
    }
}

private enum ScrobbleStoreError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        "Enter your Last.fm username and password."
    }
}

// Dynamic Theme delegating to AppModel settings
struct Theme {
    static var accent: Color { AppModel.currentAccent }
    static var accent2: Color { AppModel.currentAccent2 }
    static var bg: Color { Color(uiColor: .systemBackground) }

    static var gradient: LinearGradient {
        AppModel.currentGradient
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct Backdrop: View {
    var body: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
    }
}

// MARK: - Offline View
struct OfflineView: View {
    @EnvironmentObject var net: NetworkMonitor
    @EnvironmentObject var store: ScrobbleStore
    @Binding var dismissed: Bool

    var body: some View {
        ZStack {
            Backdrop()
            
            VStack(spacing: 22) {
                Spacer()
                
                Image(systemName: "wifi.slash")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                    .padding(28)
                
                VStack(spacing: 8) {
                    Text("You're offline")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    
                    Text("Tonal needs a connection to load your stats. Anything you scrobble meanwhile is saved and sent automatically once you're back online.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if !store.pending.isEmpty {
                    Label("\(store.pending.count) scrobble\(store.pending.count == 1 ? "" : "s") waiting to send", systemImage: "tray.full.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                
                Button(action: {
                    net.recheck()
                }) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button("Continue offline") {
                    dismissed = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(28)
        }
    }
}
