//
//  SPUSignatures.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/9/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

@objc public enum SUSigningInputStatus: UInt8 {
    /// An input was not provided at all.
    case absent = 0

    /// An input was provided, but did not have the correct format.
    case invalid

    /// An input was provided and can be used for verifying signing information.
    case present
}

@objc public final class SUSignatures: NSObject, NSSecureCoding {
    
    @objc public let dsaSignature: Data?
    @objc public let dsaSignatureStatus: SUSigningInputStatus
    
    @objc public let ed25519Signature: [UInt8]?
    @objc public let ed25519SignatureStatus: SUSigningInputStatus
    
    @objc public init(dsa: String?, ed: String?) {
        self.dsaSignature = dsa.flatMap { Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        self.dsaSignatureStatus = (dsa == nil ? .absent : (self.dsaSignature == nil ? .invalid : .present))
        
        self.ed25519Signature = ed.flatMap {
            Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.flatMap {
            guard $0.count == 64 else { return nil }
            return [UInt8]($0)
        }
        self.ed25519SignatureStatus = (ed == nil ? .absent : (self.ed25519Signature == nil ? .invalid : .present))
        
        super.init()
    }
    
    private enum NSCodingKeys: String {
        case SUDASignature, SUDSASignatureStatus, SUEDSignature, SUEDSignatureStatus
    }

    @objc public static var supportsSecureCoding: Bool { true }
    
    @objc public init?(coder: NSCoder) {
        guard let rawDsaValue = UInt8(exactly: coder.decodeInteger(forKey: NSCodingKeys.SUDSASignatureStatus.rawValue)),
              let dsaStatus = SUSigningInputStatus(rawValue: rawDsaValue)
        else {
            return nil
        }
        guard let rawEdValue = UInt8(exactly: coder.decodeInteger(forKey: NSCodingKeys.SUEDSignatureStatus.rawValue)),
              let edStatus = SUSigningInputStatus(rawValue: rawEdValue)
        else {
            return nil
        }
        let dsaSignature = coder.decodeObject(of: NSData.self, forKey: NSCodingKeys.SUDASignature.rawValue) as Data?
        let edSignature = coder.decodeObject(of: NSData.self, forKey: NSCodingKeys.SUEDSignature.rawValue) as Data?
        
        guard edSignature.map({ $0.count == 64 }) ?? true else {
            return nil
        }
        
        self.dsaSignatureStatus = dsaStatus
        self.dsaSignature = dsaSignature
        self.ed25519SignatureStatus = edStatus
        self.ed25519Signature = edSignature.map { .init($0) }
    }
    
    @objc public func encode(with coder: NSCoder) {
        coder.encode(Int(self.dsaSignatureStatus.rawValue), forKey: NSCodingKeys.SUDSASignatureStatus.rawValue)
        coder.encode(Int(self.ed25519SignatureStatus.rawValue), forKey: NSCodingKeys.SUEDSignatureStatus.rawValue)
        self.dsaSignature.map { coder.encode($0 as NSData?, forKey: NSCodingKeys.SUDASignature.rawValue) }
        self.ed25519Signature.map { coder.encode(Data($0) as NSData?, forKey: NSCodingKeys.SUEDSignature.rawValue) }
    }
}

@objc public final class SUPublicKeys: NSObject {

    @objc public let dsaPubKey: String?
    @objc public var dsaPubKeyStatus: SUSigningInputStatus { self.dsaPubKey != nil ? .present : .absent }

    @objc public let ed25519PubKey: [UInt8]?
    @objc public let ed25519PubKeyStatus: SUSigningInputStatus
    
    @objc public var hasAnyKeys: Bool { self.dsaPubKeyStatus != .absent || self.ed25519PubKeyStatus != .absent }

    @objc public init(dsa: String?, ed: String?) {
        self.dsaPubKey = dsa
        self.ed25519PubKey = ed.flatMap {
            Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.flatMap {
            guard $0.count == 32 else { return nil }
            return [UInt8]($0)
        }
        self.ed25519PubKeyStatus = (ed == nil ? .absent : (self.ed25519PubKey == nil ? .invalid : .present))
        super.init()
    }
}
