public func create_crypto_core() throws -> ClassicCryptoCore {
    try { let val = __swift_bridge__$create_crypto_core(); if val.is_ok { return ClassicCryptoCore(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
}
public func destroy_crypto_core(_ core: ClassicCryptoCore) {
    __swift_bridge__$destroy_crypto_core({core.isOwned = false; return core.ptr;}())
}
public func export_registration_bundle_b64(_ core: ClassicCryptoCoreRef) throws -> RegistrationBundleB64 {
    try { let val = __swift_bridge__$export_registration_bundle_b64(core.ptr); switch val.tag { case __swift_bridge__$ResultRegistrationBundleB64AndString$ResultOk: return val.payload.ok.intoSwiftRepr() case __swift_bridge__$ResultRegistrationBundleB64AndString$ResultErr: throw RustString(ptr: val.payload.err) default: fatalError() } }()
}
public func export_registration_bundle_json(_ core: ClassicCryptoCoreRef) throws -> RustString {
    try { let val = __swift_bridge__$export_registration_bundle_json(core.ptr); if val.is_ok { return RustString(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
}
public func init_session<GenericToRustStr: ToRustStr>(_ core: ClassicCryptoCoreRefMut, _ contact_id: GenericToRustStr, _ recipient_bundle: UnsafeBufferPointer<UInt8>) throws -> RustString {
    return contact_id.toRustStr({ contact_idAsRustStr in
        try { let val = __swift_bridge__$init_session(core.ptr, contact_idAsRustStr, recipient_bundle.toFfiSlice()); if val.is_ok { return RustString(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
    })
}
public func encrypt_message<GenericToRustStr: ToRustStr>(_ core: ClassicCryptoCoreRefMut, _ session_id: GenericToRustStr, _ plaintext: GenericToRustStr) throws -> RustVec<UInt8> {
    return plaintext.toRustStr({ plaintextAsRustStr in
        return session_id.toRustStr({ session_idAsRustStr in
        try { let val = __swift_bridge__$encrypt_message(core.ptr, session_idAsRustStr, plaintextAsRustStr); if val.is_ok { return RustVec(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
    })
    })
}
public func decrypt_message<GenericToRustStr: ToRustStr>(_ core: ClassicCryptoCoreRefMut, _ session_id: GenericToRustStr, _ ciphertext: UnsafeBufferPointer<UInt8>) throws -> RustString {
    return session_id.toRustStr({ session_idAsRustStr in
        try { let val = __swift_bridge__$decrypt_message(core.ptr, session_idAsRustStr, ciphertext.toFfiSlice()); if val.is_ok { return RustString(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
    })
}

public class ClassicCryptoCore: ClassicCryptoCoreRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$ClassicCryptoCore$_free(ptr)
        }
    }
}
public class ClassicCryptoCoreRefMut: ClassicCryptoCoreRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class ClassicCryptoCoreRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension ClassicCryptoCore: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_ClassicCryptoCore$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_ClassicCryptoCore$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: ClassicCryptoCore) {
        __swift_bridge__$Vec_ClassicCryptoCore$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_ClassicCryptoCore$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (ClassicCryptoCore(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<ClassicCryptoCoreRef> {
        let pointer = __swift_bridge__$Vec_ClassicCryptoCore$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return ClassicCryptoCoreRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<ClassicCryptoCoreRefMut> {
        let pointer = __swift_bridge__$Vec_ClassicCryptoCore$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return ClassicCryptoCoreRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<ClassicCryptoCoreRef> {
        UnsafePointer<ClassicCryptoCoreRef>(OpaquePointer(__swift_bridge__$Vec_ClassicCryptoCore$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_ClassicCryptoCore$len(vecPtr)
    }
}

public struct RegistrationBundleB64 {
    public var identity_public: RustString
    public var signed_prekey_public: RustString
    public var signature: RustString
    public var verifying_key: RustString
    public var suite_id: RustString

    public init(identity_public: RustString,signed_prekey_public: RustString,signature: RustString,verifying_key: RustString,suite_id: RustString) {
        self.identity_public = identity_public
        self.signed_prekey_public = signed_prekey_public
        self.signature = signature
        self.verifying_key = verifying_key
        self.suite_id = suite_id
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$RegistrationBundleB64 {
        { let val = self; return __swift_bridge__$RegistrationBundleB64(identity_public: { let rustString = val.identity_public.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), signed_prekey_public: { let rustString = val.signed_prekey_public.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), signature: { let rustString = val.signature.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), verifying_key: { let rustString = val.verifying_key.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), suite_id: { let rustString = val.suite_id.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$RegistrationBundleB64 {
    @inline(__always)
    func intoSwiftRepr() -> RegistrationBundleB64 {
        { let val = self; return RegistrationBundleB64(identity_public: RustString(ptr: val.identity_public), signed_prekey_public: RustString(ptr: val.signed_prekey_public), signature: RustString(ptr: val.signature), verifying_key: RustString(ptr: val.verifying_key), suite_id: RustString(ptr: val.suite_id)); }()
    }
}
extension __swift_bridge__$Option$RegistrationBundleB64 {
    @inline(__always)
    func intoSwiftRepr() -> Optional<RegistrationBundleB64> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<RegistrationBundleB64>) -> __swift_bridge__$Option$RegistrationBundleB64 {
        if let v = val {
            return __swift_bridge__$Option$RegistrationBundleB64(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$RegistrationBundleB64(is_some: false, val: __swift_bridge__$RegistrationBundleB64())
        }
    }
}


