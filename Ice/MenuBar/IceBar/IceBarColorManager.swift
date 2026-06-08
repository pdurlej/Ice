//
//  IceBarColorManager.swift
//  Ice
//

import Combine
import SwiftUI

final class IceBarColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceBarPanel: IceBarPanel?

    private var windowImage: CGImage?

    private var cancellables = Set<AnyCancellable>()

    /// Serial queue for the window-server image capture. On macOS 26 the
    /// capture (ScreenCapture.captureWindows → SkyLight) can block for
    /// seconds; running it on the main run loop froze the app (Sentry:
    /// repeated "App Hanging ≥ 2000 ms" in this exact path). The capture is
    /// CoreGraphics / CGWindowList and safe off-main — only the @Published
    /// `colorInfo` update must hop back to the main thread.
    private let captureQueue = DispatchQueue(
        label: "com.jordanbaird.Ice.IceBarColorManager.capture",
        qos: .userInitiated
    )

    /// Coalesces capture requests: while one capture is in flight, further
    /// requests are skipped (the latest state is captured by the in-flight run
    /// or the next trigger), so an event storm can't queue up captures.
    private var isCapturing = false

    func performSetup(with iceBarPanel: IceBarPanel) {
        self.iceBarPanel = iceBarPanel
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let iceBarPanel {
            iceBarPanel.publisher(for: \.screen)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] screen in
                    guard
                        let self,
                        let screen,
                        screen == .main
                    else {
                        return
                    }
                    updateWindowImage(for: screen)
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak iceBarPanel] isVisible in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        isVisible,
                        screen == .main
                    else {
                        return
                    }
                    updateColorInfo(with: iceBarPanel.frame, screen: screen)
                }
                .store(in: &c)

            iceBarPanel.publisher(for: \.frame)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self, weak iceBarPanel] frame in
                    guard
                        let self,
                        let iceBarPanel,
                        let screen = iceBarPanel.screen,
                        iceBarPanel.isVisible,
                        screen == .main
                    else {
                        return
                    }
                    withAnimation(.interactiveSpring) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

            Publishers.Merge4(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                    .replace(with: ()),
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ()),
                DistributedNotificationCenter.default()
                    .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                    .replace(with: ()),
                Timer.publish(every: 5, on: .main, in: .default)
                    .autoconnect()
                    .replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak iceBarPanel] in
                guard
                    let self,
                    let iceBarPanel,
                    let screen = iceBarPanel.screen,
                    screen == .main
                else {
                    return
                }
                updateWindowImage(for: screen) { [weak self, weak iceBarPanel] in
                    guard
                        let self,
                        let iceBarPanel,
                        iceBarPanel.isVisible
                    else {
                        return
                    }
                    withAnimation {
                        self.updateColorInfo(with: iceBarPanel.frame, screen: screen)
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    /// Refreshes `windowImage` by capturing the menu-bar + wallpaper image
    /// OFF the main thread, then runs `completion` on the main thread once the
    /// new image is stored. Never blocks the main run loop.
    private func updateWindowImage(for screen: NSScreen, completion: (() -> Void)? = nil) {
        guard !isCapturing else {
            // A capture is already running; don't queue another. Still let the
            // caller proceed (e.g. recolor from the previously captured image).
            completion?()
            return
        }
        isCapturing = true
        let displayID = screen.displayID
        captureQueue.async { [weak self] in
            let image = Self.captureWindowImage(displayID: displayID)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCapturing = false
                if let image {
                    self.windowImage = image
                }
                completion?()
            }
        }
    }

    /// Pure capture step: enumerates windows and captures the menu-bar +
    /// wallpaper image for `displayID`. No side effects; safe off the main
    /// thread (CGWindowList + the CoreGraphics capture are thread-safe).
    private static func captureWindowImage(displayID: CGDirectDisplayID) -> CGImage? {
        let windows = WindowInfo.createWindows(option: .onScreen)
        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return nil
        }
        return ScreenCapture.captureWindows(
            with: [menuBarWindow.windowID, wallpaperWindow.windowID],
            screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
            option: .nominalResolution
        )
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0...1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether its image contributed to the average.
        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        updateWindowImage(for: screen) { [weak self] in
            self?.updateColorInfo(with: frame, screen: screen)
        }
    }
}
