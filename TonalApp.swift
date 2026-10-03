import SwiftUI
import Combine
import UIKit

@main
struct TonalApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var net = NetworkMonitor()
    @StateObject private var store = ScrobbleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(net)
                .environmentObject(store)
        }
    }
}

// MARK: - Haptic Feedback Manager

enum Haptics {
    static func trigger(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard AppModel.sharedCurrent?.hapticsEnabled == true else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard AppModel.sharedCurrent?.hapticsEnabled == true else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    static func selection() {
        guard AppModel.sharedCurrent?.hapticsEnabled == true else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

// MARK: - AppModel

@MainActor
final class AppModel: ObservableObject {
    @Published var username: String { didSet { UserDefaults.standard.set(username, forKey: "username") } }
    @Published var onboarded: Bool { didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") } }
    @Published var appearanceMode: AppearanceMode { didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") } }
    @Published var accentOption: AccentColorOption { didSet { UserDefaults.standard.set(accentOption.rawValue, forKey: "accentOption") } }
    @Published var customHex: String { didSet { UserDefaults.standard.set(customHex, forKey: "customHex") } }
    @Published var fontStyle: FontStyleOption { didSet { UserDefaults.standard.set(fontStyle.rawValue, forKey: "fontStyle") } }
    @Published var glassStyle: GlassStyleOption { didSet { UserDefaults.standard.set(glassStyle.rawValue, forKey: "glassStyle") } }
    @Published var cornerRadiusStyle: CornerRadiusStyle { didSet { UserDefaults.standard.set(cornerRadiusStyle.rawValue, forKey: "cornerRadiusStyle") } }
    @Published var defaultTab: DefaultTabOption { didSet { UserDefaults.standard.set(defaultTab.rawValue, forKey: "defaultTab") } }
    
    // Additional Customization & Privacy Settings
    @Published var hapticsEnabled: Bool { didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    @Published var dataSaverEnabled: Bool { didSet { UserDefaults.standard.set(dataSaverEnabled, forKey: "dataSaverEnabled") } }
    @Published var autoTimestampScrobble: Bool { didSet { UserDefaults.standard.set(autoTimestampScrobble, forKey: "autoTimestampScrobble") } }
    @Published var soundEffectsEnabled: Bool { didSet { UserDefaults.standard.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") } }
    @Published var showGlobalListeners: Bool { didSet { UserDefaults.standard.set(showGlobalListeners, forKey: "showGlobalListeners") } }
    @Published var showMilestoneCard: Bool { didSet { UserDefaults.standard.set(showMilestoneCard, forKey: "showMilestoneCard") } }
    @Published var showPersonalityCard: Bool { didSet { UserDefaults.standard.set(showPersonalityCard, forKey: "showPersonalityCard") } }
    @Published var showTimeSpectrum: Bool { didSet { UserDefaults.standard.set(showTimeSpectrum, forKey: "showTimeSpectrum") } }
    @Published var relativeDates: Bool { didSet { UserDefaults.standard.set(relativeDates, forKey: "relativeDates") } }

    @Published var selectedTab: Int = 0

    static private(set) var sharedCurrent: AppModel?

    init() {
        let d = UserDefaults.standard
        username = d.string(forKey: "username") ?? Config.defaultUsername
        onboarded = d.bool(forKey: "onboarded")
        
        let modeStr = d.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        appearanceMode = AppearanceMode(rawValue: modeStr) ?? .system
        
        let accentStr = d.string(forKey: "accentOption") ?? AccentColorOption.purple.rawValue
        accentOption = AccentColorOption(rawValue: accentStr) ?? .purple
        
        customHex = d.string(forKey: "customHex") ?? "#A855F7"

        let fontStr = d.string(forKey: "fontStyle") ?? FontStyleOption.rounded.rawValue
        fontStyle = FontStyleOption(rawValue: fontStr) ?? .rounded

        let glassStr = d.string(forKey: "glassStyle") ?? GlassStyleOption.vibrant.rawValue
        glassStyle = GlassStyleOption(rawValue: glassStr) ?? .vibrant

        let cornerStr = d.string(forKey: "cornerRadiusStyle") ?? CornerRadiusStyle.extraRounded.rawValue
        cornerRadiusStyle = CornerRadiusStyle(rawValue: cornerStr) ?? .extraRounded

        let tabStr = d.string(forKey: "defaultTab") ?? DefaultTabOption.stats.rawValue
        let defTab = DefaultTabOption(rawValue: tabStr) ?? .stats
        defaultTab = defTab
        selectedTab = defTab.tagIndex

        hapticsEnabled = d.object(forKey: "hapticsEnabled") != nil ? d.bool(forKey: "hapticsEnabled") : true
        dataSaverEnabled = d.bool(forKey: "dataSaverEnabled")
        autoTimestampScrobble = d.object(forKey: "autoTimestampScrobble") != nil ? d.bool(forKey: "autoTimestampScrobble") : true
        soundEffectsEnabled = d.object(forKey: "soundEffectsEnabled") != nil ? d.bool(forKey: "soundEffectsEnabled") : true
        showGlobalListeners = d.object(forKey: "showGlobalListeners") != nil ? d.bool(forKey: "showGlobalListeners") : true
        showMilestoneCard = d.object(forKey: "showMilestoneCard") != nil ? d.bool(forKey: "showMilestoneCard") : true
        showPersonalityCard = d.object(forKey: "showPersonalityCard") != nil ? d.bool(forKey: "showPersonalityCard") : true
        showTimeSpectrum = d.object(forKey: "showTimeSpectrum") != nil ? d.bool(forKey: "showTimeSpectrum") : true
        relativeDates = d.object(forKey: "relativeDates") != nil ? d.bool(forKey: "relativeDates") : true
        
        AppModel.sharedCurrent = self
    }

    static var currentAccent: Color {
        guard let app = sharedCurrent else { return Color(red: 0.65, green: 0.35, blue: 0.95) }
        if app.accentOption == .custom {
            return hexToColor(app.customHex)
        }
        return app.accentOption.primary
    }

    static var currentAccent2: Color {
        guard let app = sharedCurrent else { return Color(red: 0.90, green: 0.40, blue: 0.75) }
        if app.accentOption == .custom {
            return hexToColor(app.customHex).opacity(0.65)
        }
        return app.accentOption.secondary
    }

    static var currentGradient: LinearGradient {
        LinearGradient(
            colors: [currentAccent, currentAccent2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func hexToColor(_ hex: String) -> Color {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if clean.count == 6 { clean += "FF" }
        guard clean.count == 8, let val = UInt64(clean, radix: 16) else {
            return Color(red: 0.65, green: 0.35, blue: 0.95)
        }
        let r = Double((val >> 24) & 0xFF) / 255.0
        let g = Double((val >> 16) & 0xFF) / 255.0
        let b = Double((val >> 8) & 0xFF) / 255.0
        let a = Double(val & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    static func colorToHex(_ color: Color) -> String {
        let uic = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Animated Centered Splash Screen (No Text, Preferred Color Scheme)

struct SplashScreenView: View {
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // Perfectly Centered Icon in Preferred Color Scheme
            VStack {
                ZStack {
                    // Pulsing Gradient Backdrop Aura
                    Circle()
                        .fill(Theme.gradient.opacity(0.28))
                        .frame(width: 180, height: 180)
                        .scaleEffect(scale)
                        .blur(radius: 14)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                }
            }
        }
    }
}

// MARK: - RootView

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var net: NetworkMonitor
    @EnvironmentObject var store: ScrobbleStore
    @State private var dismissed = false
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if app.onboarded {
                TabView(selection: $app.selectedTab) {
                    DashboardView().tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }.tag(0)
                    HistoryView().tabItem { Label("History", systemImage: "chart.xyaxis.line") }.tag(1)
                    SearchView().tabItem { Label("Explore", systemImage: "sparkles") }.tag(2)
                    ScrobbleView().tabItem { Label("Scrobble", systemImage: "plus.circle.fill") }.tag(3)
                    MeView().tabItem { Label("Me", systemImage: "person.crop.circle") }.tag(4)
                }
                .tint(Theme.accent)
                .id(net.reconnects)
            } else {
                OnboardingView()
            }
            
            if !net.online && !dismissed && !showSplash {
                OfflineView(dismissed: $dismissed)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .animation(.easeInOut(duration: 0.3), value: net.online)
        .animation(.easeInOut(duration: 0.3), value: dismissed)
        .preferredColorScheme(app.appearanceMode.colorScheme)
        .fontDesign(app.fontStyle.design)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
        .onChange(of: net.online) { online in
            if online { dismissed = false }
        }
        .onChange(of: net.reconnects) { _ in
            Task { [store] in
                await store.flush()
            }
        }
        .task { [store] in
            await store.flush()
        }
    }
}
