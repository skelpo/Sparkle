//
//  SPUBundleIcon.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/9/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

@objc public final class SUBundleIcon: NSObject {

    // Note: To obtain the most current bundle icon file from the Info dictionary, this should take a SUHost, not a NSBundle
    @objc public static func iconURL(forHost host: SUHost) -> URL? {
        return (host.object(forInfoDictionaryKey: "CFBundleIconFile") as? String).flatMap {
            host.bundle.url(forResource: $0, withExtension: "icns") ??
            host.bundle.url(forResource: $0, withExtension: nil)
        }
    }
}
