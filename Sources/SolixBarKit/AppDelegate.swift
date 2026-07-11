import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Doppelstart-Schutz: zweite Instanz aktiviert die erste und beendet
        // sich (zwei Instanzen ergaeben zwei Statusitems und Schreibkonflikte).
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate()
                AppLogger.info("Second instance detected; terminating in favor of PID \(existing.processIdentifier).")
                NSApp.terminate(nil)
                return
            }
        }
        UserDefaults.standard.set(0.1, forKey: "NSInitialToolTipDelay")
        AppLogger.info("SolixBar \(AppVersion.display) started. Log: \(AppLogger.logURL.path)")
        statusController = StatusController()
        statusController?.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusController?.prepareForTermination()
        AppLogger.info("SolixBar terminated.")
    }
}
