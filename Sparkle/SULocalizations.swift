//
//  SULocalizations.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

public func SULocalizedString(_ key: String, _ comment: String? = nil) -> String {
    return NSLocalizedString(key, tableName: "Sparkle", bundle: Bundle(identifier: SUBundleIdentifier) ?? Bundle.main, comment: comment!)
}
