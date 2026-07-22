public enum MenuBarIconPolicy {
    public static func shouldShowAppIcon(
        settingIsEnabled: Bool,
        detachedBarIsOpen: Bool
    ) -> Bool {
        // The detached bar has its own icon setting and must not override the regular menu bar.
        _ = detachedBarIsOpen
        return settingIsEnabled
    }
}
