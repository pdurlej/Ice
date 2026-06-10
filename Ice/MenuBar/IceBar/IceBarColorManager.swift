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
        let captured = ScreenCapture.captureWindows(
            with: [menuBarWindow.windowID, wallpaperWindow.windowID],
            screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
            option: .nominalResolution
        )
        // CRITICAL (fire.10.1): CGWindowList images are LAZY — their pixels are
        // fetched from the window server only when first DRAWN
        // (CGSCaptureImageProviderBytePointer). fire.9.9 moved the capture call
        // off-main but handed this lazy image to the main thread, so the slow
        // macOS-26 fetch still happened inside `averageColor()`'s draw on the
        // main run loop → residual "App Hanging ≥ 2000 ms" (Sentry FIRE-D, on
        // fire.10.0). Force materialization HERE, on the capture queue, so the
        // main thread only ever sees a resident bitmap. FAIL CLOSED: if
        // materialization fails we return nil (caller keeps the previous
        // resident image) rather than leak a lazy image back to main — that
        // silent fallback is exactly what made the 9.9 fix a half-fix
        // (GPT-5.5 Pro review, ~/.oracle/sessions/fire-icebar-anr-materializ-review).
        return captured.flatMap(materialized)
    }

    /// Draws a (possibly window-server-backed, lazy) CGImage into a detached
    /// RGBA bitmap and returns the RESIDENT copy. The expensive window-server
    /// pixel fetch happens at THIS draw — so it must be called off the main
    /// thread. Returns `nil` (fail closed) if a context can't be made or the
    /// bitmap can't be realized: the caller then keeps the last good resident
    /// image, so a lazy image is NEVER handed to the main thread.
    private static func materialized(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let preferredSpace: CGColorSpace? = {
            if let space = image.colorSpace, space.model == .rgb {
                return space
            }
            return CGColorSpace(name: CGColorSpace.displayP3)
        }()
        let fallbackSpace = CGColorSpaceCreateDeviceRGB()

        func makeContext(_ space: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: bitmapInfo
            )
        }

        guard let context = (preferredSpace.flatMap(makeContext)) ?? makeContext(fallbackSpace) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // No `?? image` fallback: makeImage() failure returns nil (fail closed).
        return context.makeImage()
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
