//
//  SUInstallerLauncherStatus.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/18/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

@objc public enum SUInstallerLauncherStatus: UInt, Hashable {
    case success = 0, canceled = 1, authorizeLater = 3, failure = 4
}
