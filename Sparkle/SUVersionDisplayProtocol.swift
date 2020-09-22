//
//  SUVersionDisplayProtocol.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

/*
@objc public protocol SUVersionDisplay: NSObjectProtocol {
    @objc(formatVersion:andVersion:)
    func __formatVersion(
        _ inOutVersionA: AutoreleasingUnsafeMutablePointer<NSString>,
        andVersion inOutVersionB: AutoreleasingUnsafeMutablePointer<NSString>
    )
}
*/

extension SUVersionDisplay {
    public func format(version versionA: String, and versionB: String) -> (versionA: String, versionB: String) {
        var bridgedVersionA = versionA as NSString
        var bridgedVersionB = versionB as NSString
        
        self.__formatVersion(&bridgedVersionA, andVersion: &bridgedVersionB)
        
        return (versionA: bridgedVersionA as String, versionB: bridgedVersionB as String)
    }
}
