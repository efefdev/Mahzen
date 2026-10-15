import AppKit
import MahzenCore
import SwiftUI

/// Kilit ve karşılama ekranlarının arka planı: vurgu renginde, yavaşça dalgalanan ışık.
/// "Hareketi azalt" açıksa sabit durur.
struct AuraBackground: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        let accent = state.accent.color
        // Turuncuda geniş renk kayması sarı-yeşile kaçar; marka rengi sıcak tonlarda kalsın.
        let spread: Double = state.accent == .orange ? 12 : 45
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    Circle()
                        .fill(accent.opacity(scheme == .dark ? 0.55 : 0.35))
                        .frame(width: w * 0.75)
                        .offset(x: drift ? -w * 0.28 : -w * 0.12, y: drift ? -h * 0.30 : -h * 0.12)
                    Circle()
                        .fill(accent.opacity(scheme == .dark ? 0.40 : 0.25))
                        .hueRotation(.degrees(spread))
                        .frame(width: w * 0.6)
                        .offset(x: drift ? w * 0.30 : w * 0.18, y: drift ? h * 0.22 : h * 0.34)
                    Circle()
                        .fill(accent.opacity(scheme == .dark ? 0.30 : 0.18))
                        .hueRotation(.degrees(-spread * 0.9))
                        .frame(width: w * 0.45)
                        .offset(x: drift ? w * 0.05 : -w * 0.08, y: drift ? h * 0.05 : -h * 0.02)
                }
                .blur(radius: min(w, h) * 0.14)
                RadialGradient(
                    colors: [.clear, (scheme == .dark ? Color.black : Color.white).opacity(scheme == .dark ? 0.45 : 0.35)],
                    center: .center, startRadius: min(w, h) * 0.25, endRadius: max(w, h) * 0.75
                )
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Mahzen logosu, alttan turuncu bir ışıltıyla. Kilit açılırken anahtar deliği parlar.
struct VaultBadge: View {
    var size: CGFloat = 76
    var open = false

    var body: some View {
        MahzenLogo(open: open)
            .frame(width: size, height: size)
            .scaleEffect(1.2) // logo kendi tuvalinde kenar boşluğu bırakır; rozet boyutunu korumak için
            .frame(width: size, height: size)
            .shadow(color: MahzenLogo.glowColor.opacity(0.35), radius: size * 0.2, y: size * 0.08)
    }
}

struct Card<Content: View>: View {
    var width: CGFloat = 420
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(32)
            .frame(width: width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 40, y: 16)
    }
}

struct StrengthMeter: View {
    let password: String

    var body: some View {
        let strength = PasswordStrength.evaluate(password)
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(i <= strength.score && !password.isEmpty ? color(strength.score) : Color.secondary.opacity(0.2))
                        .frame(height: 5)
                }
            }
            Text(password.isEmpty ? " " : strength.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(password.isEmpty ? Color.secondary : color(strength.score))
                .frame(width: 70, alignment: .trailing)
        }
        .animation(.snappy, value: strength.score)
    }

    func color(_ score: Int) -> Color {
        [Color.red, .orange, .yellow, .green, .teal][score]
    }
}

/// Göz düğmeli parola alanı.
struct RevealableField: View {
    @Environment(\.vaultAccent) private var accent
    let title: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if reveal {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit(onSubmit)
            Button {
                reveal.toggle()
                focused = true
            } label: {
                Image(systemName: reveal ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(reveal ? "Gizle" : "Göster")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(focused ? accent.opacity(0.7) : Color.secondary.opacity(0.25)))
    }
}

struct ProgressOverlay: View {
    let task: TaskProgress
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                if let fraction = task.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                } else {
                    ProgressView().controlSize(.large)
                }
                Text(task.title).font(.headline)
                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300)
                }
                if task.cancellable {
                    Button("Durdur") { state.cancelTask() }.controlSize(.small)
                }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 20)
        }
        .transition(.opacity)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bir değeri ve kopyalama düğmesini gösteren satır.
struct FieldRow<Value: View>: View {
    let label: String
    var copyValue: String?
    var sensitive = false
    @ViewBuilder var value: Value
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                value.textSelection(.enabled)
            }
            Spacer()
            if let copyValue, !copyValue.isEmpty {
                Button {
                    state.copy(copyValue, sensitive: sensitive, label: "\(label) kopyalandı")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Kopyala")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}
