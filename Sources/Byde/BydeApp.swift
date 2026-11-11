import ServiceManagement
import SwiftUI

@main
struct BydeApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @ObservedObject var engine = Engine.shared
    @ObservedObject var link = LinkStore.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        if CommandLine.arguments.contains("--selftest") { Schedule.selfTest(); Log.selfTest(); exit(0) }
    }

    var body: some Scene {
        MenuBarExtra {
            Text(engine.statusLine)
            Menu("Meditate now") {
                ForEach([3, 5, 10], id: \.self) { n in Button("\(n) min") { engine.meditate(n, source: "menu") } }
                if link.isSet {
                    Divider()
                    Button { engine.linkSession(source: "menu-link") } label: {
                        Label { Text(link.title) } icon: { Image(nsImage: link.menuImage) }
                    }
                }
            }
            .disabled(engine.sessionEnd != nil)
            Divider()
            Button("Settings…") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "settings") }
            Button("About Byde") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "about") }
            #if DEBUG
            Menu("Debug") {
                Button("Show today's nudge schedule") { engine.debug("schedule") }
                Divider()
                Button("Nudge 1") { engine.debug("nudge1") }
                Button("Nudge 2") { engine.debug("nudge2") }
                Button("Nudge 3") { engine.debug("nudge3") }
                Divider()
                Button("Refetch favicon") { engine.debug("refetchFavicon") }
                Divider()
                Button("Icon: show waiting") { engine.debug("iconWaiting") }
                Button("Icon: show done") { engine.debug("iconDone") }
                Divider()
                Button("Reset today") { engine.debug("reset") }
                Button("Reveal log") { engine.debug("reveal") }
            }
            #endif
            Divider()
            Button("Quit Byde") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: MenuIcon.image(done: engine.iconDone))
        }
        Window("Settings", id: "settings") { SettingsView() }
            .windowResizability(.contentSize)
        Window("About Byde", id: "about") { AboutView() }
            .windowResizability(.contentSize)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Engine.shared.start()
    }
}

private func time(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date())! },
        set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = c.hour! * 60 + c.minute! })
}

/// M T W T F S S as joined toggle buttons. `days` holds Calendar weekday numbers (1 = Sunday), comma-separated.
struct DaysPicker: View {
    @Binding var days: String
    private let order: [(num: Int, label: String, name: String)] = [
        (2, "M", "Monday"), (3, "T", "Tuesday"), (4, "W", "Wednesday"), (5, "T", "Thursday"),
        (6, "F", "Friday"), (7, "S", "Saturday"), (1, "S", "Sunday")]
    private var selected: Set<Int> { Set(days.split(separator: ",").compactMap { Int($0) }) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.offset) { i, d in
                let on = selected.contains(d.num)
                Button { toggle(d.num) } label: {
                    Text(d.label)
                        .frame(width: 30, height: 24)
                        .background(on ? Theme.accent : Color.clear)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.name)
                .accessibilityAddTraits(on ? .isSelected : [])
                if i < order.count - 1 { Theme.divider.frame(width: 0.5, height: 24) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.divider, lineWidth: 0.5))
    }

    private func toggle(_ n: Int) {
        var s = selected
        if s.contains(n) { s.remove(n) } else { s.insert(n) }
        days = s.sorted().map(String.init).joined(separator: ",")
    }
}

enum Theme {
    static let accent = Color(red: 0x3E / 255, green: 0x6A / 255, blue: 0x8A / 255)
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light) })
    }
    /// Light window with grey cards; in dark mode the cards are lighter than the window.
    static let window = dynamic(light: 0xFAFAFA, dark: 0x1C1C1E)
    static let card = dynamic(light: 0xF0F0F2, dark: 0x2C2C2E)
    static let divider = dynamic(light: 0xDCDCE0, dark: 0x3F3F42)
}

/// Transparent title bar, no separator, content extending beneath it (Settings and About windows).
/// `about`: also hides the title text, makes the window non-resizable and centres it when it first opens.
/// Applied when the view reaches its window, so it doesn't depend on SwiftUI updating the view afterwards.
private struct TitlebarBlend: NSViewRepresentable {
    var about = false
    func makeNSView(context: Context) -> NSView {
        let v = BlendView()
        v.about = about
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}

    private final class BlendView: NSView {
        var about = false
        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            apply(w)
            DispatchQueue.main.async { [weak self] in self?.apply(w) }       // once more after SwiftUI's own setup
            if about { w.center() }
        }
        private func apply(_ w: NSWindow) {
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.styleMask.insert(.fullSizeContentView)
            if about {
                w.titleVisibility = .hidden
                w.styleMask.remove(.resizable)
                w.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Byde").font(.system(size: 28, weight: .semibold)).padding(.top, 6)
            Text(version).foregroundStyle(.secondary)
            Text("A gentle nudge to meditate, once a day, inside a window you choose.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            HStack(spacing: 3) {
                Text("© 2026").foregroundStyle(.secondary)
                Button("Joshua Kaufman") { NSWorkspace.shared.open(URL(string: "https://joshuakaufman.org")!) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .font(.caption).padding(.top, 14)
            // Escape and Cmd-W close the window.
            Button("") { dismissWindow(id: "about") }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            Button("") { dismissWindow(id: "about") }.keyboardShortcut("w", modifiers: .command).opacity(0).frame(width: 0, height: 0)
        }
        .padding(.horizontal, 32)
        .frame(width: 340, height: 360)
        .background {
            Theme.window.ignoresSafeArea()
            TitlebarBlend(about: true)
        }
    }
}

struct SettingsView: View {
    @AppStorage("days") private var days = "2,3,4,5,6"
    @AppStorage("startMin") private var startMin = 660
    @AppStorage("endMin") private var endMin = 780
    @ObservedObject private var link = LinkStore.shared
    @State private var site = LinkStore.shared.url
    @FocusState private var siteFocused: Bool
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            card(footer: "Choose a window when you're usually free. Byde will nudge you when the window starts, again \(Int(Schedule.nudge2Delay / 60)) minutes later if you haven't started, and once more \(Int(Schedule.nudge3Lead / 60)) minutes before it ends.") {
                row("Days") { DaysPicker(days: $days) }
                divider
                row("Window starts") { DatePicker("", selection: time($startMin), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.stepperField) }
                divider
                row("Window ends") { DatePicker("", selection: time($endMin), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.stepperField) }
                if endMin <= startMin { note("The window must end after it starts.") }
            }
            card(footer: "Opens your meditation app instead of the built-in timer.") {
                row("Website (optional)") {
                    HStack(spacing: 6) {
                        TextField("e.g. app.wakingup.com", text: $site)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .focused($siteFocused)
                            .onSubmit { link.commit(site) }
                        if link.isSet {
                            Button { link.remove(); site = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove website")
                            .accessibilityLabel("Remove website")
                        }
                    }
                }
                if !link.error.isEmpty { note(link.error, error: true) }
                divider
                row("Label") {
                    HStack(spacing: 6) {
                        if link.isSet { LinkIcon() }
                        // The hidden Text gives the field its text's width, so the icon sits right next to the label.
                        Text(link.label.isEmpty ? " " : link.label)
                            .opacity(0)
                            .overlay(TextField("", text: $link.label).textFieldStyle(.plain).disabled(!link.isSet))
                    }
                }
            }
            card {
                row("Open at login") {
                    Toggle("", isOn: loginBinding).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
                if loginStatus == .requiresApproval {
                    HStack(spacing: 4) {
                        Text("Turned off in System Settings.")
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        Spacer(minLength: 0)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
                if !loginError.isEmpty { note(loginError) }
            }
        }
        .padding(20)
        .padding(.top, 12)                              // clear of the transparent title bar
        .frame(width: 420)
        .background {
            Theme.window.ignoresSafeArea()               // continues behind the title bar
            TitlebarBlend()
        }
        .tint(Theme.accent)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: siteFocused) { _, focused in if !focused { link.commit(site) } }
        .onChange(of: link.url) { _, new in site = new }
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    /// On only when the system says enabled; after any change the toggle follows the real status.
    private var loginBinding: Binding<Bool> {
        Binding(get: { loginStatus == .enabled }, set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = ""
            } catch {
                loginError = error.localizedDescription
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { loginError = "" }
            }
            loginStatus = SMAppService.mainApp.status
        })
    }

    private func card<C: View>(footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row<T: View>(_ label: String, @ViewBuilder _ trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var divider: some View { Theme.divider.frame(height: 0.5).padding(.leading, 12) }

    private func note(_ t: String, error: Bool = false) -> some View {
        Text(t).font(.caption).foregroundStyle(error ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}
