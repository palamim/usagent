import SwiftUI

@main
struct UsagentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarLabelView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: Info.plist sets LSUIElement, but `swift run`
        // during development doesn't produce a bundle, so this keeps the
        // dock icon away in both cases.
        NSApp.setActivationPolicy(.accessory)
    }
}
