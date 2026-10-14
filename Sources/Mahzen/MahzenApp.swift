import AppKit
import SwiftUI

@main
struct MahzenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Mahzen", id: "main") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Kasa") {
                Button("Kilitle") { state.lock() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(state.phase != .unlocked)
                Divider()
                Button("Dosya Ekle…") {
                    state.section = .files
                    state.presentImportPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(state.phase != .unlocked)
                Button("Yeni Not") {
                    state.section = .notes
                    state.addNote()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(state.phase != .unlocked)
                Button("Anahtar Dosyası İçe Aktar…") { state.importKeyfile() }
                    .disabled(state.phase != .locked)
                Divider()
                Button("Şimdi Yedekle") { state.backupNow() }
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(state.phase != .unlocked || state.task != nil)
                Button("Bütünlük Taraması…") { state.runIntegrityScan() }
                    .disabled(state.phase != .unlocked || state.task != nil)
                Divider()
                Button("Yeni Parola Kaydı") {
                    state.section = .secrets
                    state.newSecretRequested = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(state.phase != .unlocked)
            }
        }
    }
}

/// Kilit ve karşılama ekranında başlık çubuğunu gizler; arka plan pencerenin tamamını kaplar.
struct HiddenTitleBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
                .ignoresSafeArea()
        } else {
            content.ignoresSafeArea()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            switch state.phase {
            case .welcome: WelcomeView().modifier(HiddenTitleBar()).transition(.opacity)
            case .locked: UnlockView().modifier(HiddenTitleBar()).transition(.opacity)
            case .unlocked: MainView().transition(.opacity)
            }
            if let task = state.task { ProgressOverlay(task: task) }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Text(toast)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(state.accent.color)
        .environment(\.vaultAccent, state.accent.color)
        .animation(.smooth(duration: 0.3), value: state.phase)
        .alert(item: $state.alert) { item in
            Alert(title: Text(item.title), message: Text(item.message))
        }
        #if DEBUG
        .task { await DebugSnapshots.runIfRequested(state) }
        #endif
    }
}
