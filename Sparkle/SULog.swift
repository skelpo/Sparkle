//
//  SULog.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

public func SULog(_ level: SULogLevel, _ message: String) {
    withVaList([message as NSString]) {
        SULogv(level, "%@", $0)
    }
}
