import AppKit
import SwiftUI

/// Floating, non-activating: never takes keyboard focus from whatever you're doing.
final class FloatPanel: NSPanel {
    let host: NSHostingView<AnyView>

    init(_ view: AnyView) {
        host = NSHostingView(rootView: view)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = host
        isFloatingPanel = true
        level = .modalPanel
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom-right of the main screen's visible frame (so above the Dock), or centred.
    func present(center: Bool, animate: Bool) {
        guard let v = NSScreen.main?.visibleFrame else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let origin = center
            ? NSPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2 + v.height * 0.1)
            : NSPoint(x: v.maxX - size.width - 16, y: v.minY + 16)
        setFrame(NSRect(origin: origin, size: size), display: true, animate: animate && isVisible)
        orderFrontRegardless()
    }

    func pulse(times: Int = 2) {
        guard times > 0 else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; animator().alphaValue = 0.45 }) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; self.animator().alphaValue = 1 }) {
                self.pulse(times: times - 1)
            }
        }
    }
}

final class TimerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// Panel buttons live in a non-key window, where system prominent styles go grey — so draw our own.
// Used by the duration buttons and the meditation link button.
// `tonal`: the duration buttons when a link button is shown: the same blue at 50% opacity, white label.
struct Filled: ButtonStyle {
    var tonal = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(tonal ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Favicon on a small white rounded tile, so it stays visible on the blue button.
struct LinkTile: View {
    @ObservedObject var link = LinkStore.shared
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white)
            if let f = link.favicon {
                Image(nsImage: f).resizable().interpolation(.high).padding(2)
            } else {
                Image(systemName: "globe").foregroundStyle(Color.black.opacity(0.6)).padding(2)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct Quiet: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

private extension View {
    func card() -> some View {
        padding(16).frame(width: 344).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Nudges 1–3 (stage 3 is centred and titled with the closing time).
struct NudgeView: View {
    @ObservedObject var e = Engine.shared
    @ObservedObject var link = LinkStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            main
        }
        .card()
    }

    private var title: String {
        switch e.stage {
        case 2: return "You've got until \(e.endText)."
        case 3: return "Window ends at \(e.endText)."
        default: return e.snoozedToday ? "Ready now?" : "Ready to meditate?"
        }
    }

    private var main: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                if link.isSet {
                    Button { e.linkSession(source: "link") } label: {
                        HStack(spacing: 6) { LinkTile(); Text(link.title).lineLimit(1) }
                    }
                    .buttonStyle(Filled())
                }
                HStack(spacing: 8) {
                    ForEach([3, 5, 10], id: \.self) { n in Button("\(n) min") { e.meditate(n) }.buttonStyle(Filled(tonal: link.isSet)) }
                }
            }
            HStack(spacing: 18) {
                if e.stage != 3 {
                    Button("Snooze") { e.snooze() }
                        .help("Snooze for 10 minutes").accessibilityLabel("Snooze for 10 minutes")
                }
                Button("Already done") { e.alreadyMeditated() }
                Button("Skip today") { e.skip() }
            }
            .buttonStyle(Quiet())
            .frame(maxWidth: .infinity)
        }
    }
}

struct MeditationView: View {
    @ObservedObject var e = Engine.shared
    let leadEnd: Date
    let end: Date
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.1)
            if e.sessionOver { finished } else { running }
        }
        .ignoresSafeArea()
    }

    private var running: some View {
        VStack(spacing: 48) {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let counting = ctx.date < leadEnd
                let s = counting
                    ? min(10, max(1, Int(leadEnd.timeIntervalSince(ctx.date).rounded(.up))))
                    : max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
                Text(counting ? "\(s)" : String(format: "%d:%02d", s / 60, s % 60))
                    .font(.system(size: 120, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
            Button("End early") { e.endEarly() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var finished: some View {
        VStack(spacing: 48) {
            Text("\(e.sessionMinutes) minutes completed.")
                .font(.system(size: 64, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Button("Done") { e.finishSession() }
                .keyboardShortcut(.defaultAction)       // Return
                .buttonStyle(.bordered)
                .controlSize(.large)
            Button("") { e.finishSession() }            // Escape
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
