//
//  Shims.swift
//  FireLogic
//
//  Minimal stand-ins so the security-critical pure-logic sources (symlinked
//  from Ice/Automation/) compile in this standalone SPM module without
//  dragging in the app's AppKit/OSLog conveniences. The ONLY app helper the
//  symlinked files reference is `Logger(category:)` (Ice defines it in
//  Shared/Utilities/Logging.swift, which also pulls in `Logger(.default)` and
//  named shared loggers we don't want here).
//

import OSLog

extension Logger {
    /// Mirror of Ice's `Logger(category:)` convenience.
    init(category: String) {
        self.init(subsystem: "com.jordanbaird.Ice.firelogic", category: category)
    }
}
