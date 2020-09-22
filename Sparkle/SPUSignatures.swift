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
    
    /// A Swift view of the Ed25519 signature (if any) as an array of bytes.
    @nonobjc public let ed25519Signature: [UInt8]?
    
    /// If an Ed25519 signature exists and has been requested from Objective-C at least once, this property tracks a
    /// manually allocated buffer containing a copy of the data in `ed25519Signature`.
    private var _cachedLegacyEd25519Signature: UnsafeMutableBufferPointer<UInt8>?
    
    /// A legacy, Objective-C compatible view of the Ed25519 signature, if any, as a pointer to memory assumed to
    /// contain a specific number of bytes. This property is exposed to Objective-C callers as if it is the only view
    /// available, even though it isn't.
    @objc(ed25519Signature) public var _legacyEd25519Signature: UnsafePointer<UInt8>? {
        if let signature = self.ed25519Signature, self._cachedLegacyEd25519Signature == nil {
            signature.withUnsafeBufferPointer {
                self._cachedLegacyEd25519Signature = .allocate(capacity: $0.count)
                _ = self._cachedLegacyEd25519Signature!.initialize(from: $0)
            }
        }
        return self._cachedLegacyEd25519Signature?.baseAddress.map { .init($0) }
    }
    
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
    
    deinit {
        self._cachedLegacyEd25519Signature?.deallocate()
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

    /// A Swift view of the Ed25519 pubkey (if any) as an array of bytes.
    @nonobjc public let ed25519PubKey: [UInt8]?
    
    /// If an Ed25519 pubkey exists and has been requested from Objective-C at least once, this property tracks a
    /// manually allocated buffer containing a copy of the data in `ed25519PubKey`.
    private var _cachedLegacyEd25519PubKey: UnsafeMutableBufferPointer<UInt8>?
    
    /// A legacy, Objective-C compatible view of the Ed25519 pubkey, if any, as a pointer to memory assumed to
    /// contain a specific number of bytes. This property is exposed to Objective-C callers as if it is the only view
    /// available, even though it isn't.
    @objc(ed25519PubKey) public var _legacyEd25519PubKey: UnsafePointer<UInt8>? {
        if let pubkey = self.ed25519PubKey, self._cachedLegacyEd25519PubKey == nil {
            pubkey.withUnsafeBufferPointer {
                self._cachedLegacyEd25519PubKey = .allocate(capacity: $0.count)
                _ = self._cachedLegacyEd25519PubKey!.initialize(from: $0)
            }
        }
        return self._cachedLegacyEd25519PubKey?.baseAddress.map { .init($0) }
    }

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

    deinit {
        self._cachedLegacyEd25519PubKey?.deallocate()
    }
}
