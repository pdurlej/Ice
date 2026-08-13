//
//  main.swift
//  MenuBarItemService
//

import Foundation

AXHelpers.limitGlobalMessagingTimeout()
SourcePIDCache.shared.start()
Listener.shared.activate()
RunLoop.current.run()
