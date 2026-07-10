import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
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
