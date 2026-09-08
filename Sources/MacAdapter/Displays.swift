import AppKit
import TilerCore

public enum MacDisplays {
    // Call on the main thread; AX uses a top-left origin based on the primary screen.
    public static func read() -> [Display] {
        let screens = NSScreen.screens
        let top = screens.first?.frame.maxY ?? 0
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
            let id = CFUUIDCreateString(nil, uuid)! as String
            func rect(_ frame: NSRect) -> Rect { Rect(frame.minX, top-frame.maxY, frame.width, frame.height) }
            let frame = rect(screen.frame), usable = rect(screen.visibleFrame)
            // visibleFrame's top inset contains the menu bar; its bottom/side insets
            // contain the Dock. Retain only the top inset for manager fullscreen.
            let menuInset = max(0, usable.y-frame.y)
            let fullscreen = Rect(frame.x, frame.y+menuInset, frame.width, frame.height-menuInset)
            return Display(id: id, frame: frame, usable: usable, fullscreen: fullscreen)
        }
    }
}

public enum DockSuppression {
    public static let available = false
    public static let explanation = "Dock suppression unavailable: AppKit hideDock only applies to the active app. McTiler cannot enforce it across other apps through that API. No Dock settings have been changed."
}
