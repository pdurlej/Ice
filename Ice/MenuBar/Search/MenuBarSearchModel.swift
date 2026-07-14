//
//  MenuBarSearchModel.swift
//  Ice
//

import Cocoa
import Combine
import Ifrit

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag)
    }

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    private var cancellables = Set<AnyCancellable>()

    /// Keeps SkyLight capture and pixel averaging off the main thread.
    private let averageColorCaptureQueue = DispatchQueue(
        label: "com.jordanbaird.Ice.MenuBarSearchModel.averageColorCapture",
        qos: .userInitiated
    )

    /// Coalesces repeated panel updates while a capture is in flight.
    private var isUpdatingAverageColorInfo = false

    let fuse = Fuse(threshold: 0.5)

    func performSetup(with panel: MenuBarSearchPanel) {
        configureCancellables(with: panel)
    }

    private func configureCancellables(with panel: MenuBarSearchPanel) {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            panel.publisher(for: \.screen),
            panel.publisher(for: \.isVisible)
        )
        .compactMap { screen, isVisible in
            isVisible ? screen : nil
        }
        .sink { [weak self] screen in
            Task { await self?.updateAverageColorInfo(for: screen) }
        }
        .store(in: &c)

        cancellables = c
    }

    private func updateAverageColorInfo(for screen: NSScreen) async {
        guard !isUpdatingAverageColorInfo else { return }
        isUpdatingAverageColorInfo = true

        // createWindows enumerates the window server synchronously; fetch
        // off-main so it can't freeze the main thread (fire.10.4.1).
        let windows = await Task.detached { WindowInfo.createWindows(option: .onScreen) }.value
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            isUpdatingAverageColorInfo = false
            return
        }

        let windowIDs = [menuBarWindow.windowID, wallpaperWindow.windowID]
        let captureBounds = withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 }

        averageColorCaptureQueue.async { [weak self] in
            let color = ScreenCapture.captureWindows(
                with: windowIDs,
                screenBounds: captureBounds,
                option: .nominalResolution
            )?.averageColor(option: .ignoreAlpha)

            DispatchQueue.main.async {
                guard let self else { return }
                self.isUpdatingAverageColorInfo = false
                guard let color else { return }

                let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)
                if self.averageColorInfo != info {
                    self.averageColorInfo = info
                }
            }
        }
    }
}
