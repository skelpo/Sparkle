//
//  SUApplicationInfo.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import AppKit

@objc public final class SUApplicationInfo: NSObject {

    @objc(isBackgroundApplication:) public static func isBackground(application: NSApplication) -> Bool {
        return application.activationPolicy() == .accessory
    }
    
    @objc(bestIconForHost:) public static func bestIcon(forHost host: SUHost) -> NSImage? {
        if let image = SUBundleIcon.iconURL(forHost: host).flatMap({ NSImage(contentsOf: $0) }) {
            return image
        }
        
        // this asumption may not be correct (eg. even though we're not the main bundle, it could be still be a regular app)
        // but still better than nothing if no icon was included
        return NSWorkspace.shared.icon(forFileType: (host.bundle.isMainBundle ? kUTTypeApplication : kUTTypeBundle) as String)
    }

}
