# 🔐 Security Audit Report: Construct Messenger Rust Core

**Date**: December 27, 2025
**Auditor**: Claude Sonnet 4.5
**Scope**: Cryptographic implementation in Rust core (`packages/core`)
**Duration**: Comprehensive review + test suite development

---

## Executive Summary

### Overall Assessment: ⚠️ **MODERATE RISK**

The Rust cryptographic core demonstrates good architectural principles with the crypto-agility pattern, but contains **critical bugs** that prevent proper functionality and compromise security.

**Key Metrics:**
- ✅ 0 unsafe blocks (excellent memory safety)
- ✅ Well-structured crypto-agility architecture
- ❌ **CRITICAL:** 5/21 tests failing due to signature verification bug
- ⚠️ Missing comprehensive test coverage for core crypto
- ⚠️ Post-quantum code incomplete and non-functional

**Recommendation**: **DO NOT DEPLOY** until critical bugs are fixed and test coverage reaches ≥90%.

---

## 🔴 Critical Findings (Must Fix Immediately)

### 1. **CRITICAL: Invalid Verifying Key Generation**

**Location**: `packages/core/src/crypto/client.rs:58`

**Issue**:
```rust
pub fn get_registration_bundle(&self) -> RegistrationBundle {
    let identity_public = P::from_private_key_to_public_key(&self.identity_key).unwrap();
    let signed_prekey_public = P::from_private_key_to_public_key(&self.signed_prekey).unwrap();

    // ❌ BUG: Generates NEW verifying key instead of deriving from self.signing_key
    let (_, verifying_key_generated) = P::generate_signature_keys().unwrap();

    let signature = P::sign(&self.signing_key, signed_prekey_public.as_ref()).unwrap();

    RegistrationBundle {
        identity_public: identity_public.as_ref().to_vec(),
        signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
        signature,
        verifying_key: verifying_key_generated.as_ref().to_vec(), // ❌ WRONG KEY!
        suite_id: P::suite_id(),
    }
}
```

**Impact**: 🔴 **CRITICAL**
- Signature verification **always fails**
- Clients cannot establish sessions
- Complete protocol failure

**Root Cause**:
The verifying key in the bundle does NOT correspond to the signing key used to create the signature. This is a fundamental cryptographic error.

**Affected Tests**:
- ❌ `test_client_crypto_registration_bundle`
- ❌ `test_client_crypto_init_session`
- ❌ `test_client_crypto_message_exchange`
- ❌ `test_encryption_performance`
- ❌ `test_session_serialization`

**Fix Required**:
```rust
pub fn get_registration_bundle(&self) -> RegistrationBundle {
    let identity_public = P::from_private_key_to_public_key(&self.identity_key).unwrap();
    let signed_prekey_public = P::from_private_key_to_public_key(&self.signed_prekey).unwrap();

    // ✅ FIX: Derive verifying key from signing_key
    let verifying_key = P::from_private_key_to_public_key_signature(&self.signing_key).unwrap();

    let signature = P::sign(&self.signing_key, signed_prekey_public.as_ref()).unwrap();

    RegistrationBundle {
        identity_public: identity_public.as_ref().to_vec(),
        signed_prekey_public: signed_prekey_public.as_ref().to_vec(),
        signature,
        verifying_key: verifying_key.as_ref().to_vec(),
        suite_id: P::suite_id(),
    }
}
```

**NOTE**: This requires adding `from_private_key_to_public_key_signature` to the `CryptoProvider` trait.

---

## 🟡 High Priority Issues

### 2. **Incomplete Post-Quantum Implementation**

**Location**:
- `packages/core/src/crypto/pq_x3dh.rs`
- `packages/core/src/crypto/pq_double_ratchet.rs`
- `packages/core/src/crypto/client.rs:125-168`

**Issue**: Post-quantum code marked with `unimplemented!()` and contains compilation errors.

**Impact**: 🟡 **HIGH**
- Cannot enable `post-quantum` feature
- PQ hybrid mode non-functional
- Compilation errors when PQ feature is enabled

**Example**:
```rust
#[cfg(feature = "post-quantum")]
pub fn perform_pq_x3dh(&self, remote_bundle: &PQX3DHBundle) -> Result<[u8; 64], String> {
    unimplemented!("Classical part of PQX3DH is not implemented yet");
    unimplemented!("Post-quantum part of PQX3DH is not implemented yet");
}
```

**Recommendation**:
- Either complete PQ implementation OR remove `post-quantum` feature flag
- Document PQ roadmap in `ROADMAP.md` (already exists)

---

### 3. **No Signature Private→Public Key Derivation**

**Location**: `packages/core/src/crypto/crypto_provider.rs`

**Issue**: `CryptoProvider` trait lacks method to derive signature public key from private key.

**Impact**: 🟡 **HIGH**
- Workaround in client.rs line 58 is WRONG (see Critical Finding #1)
- Cannot restore verifying key from signing key

**Fix Required**:
Add to `CryptoProvider` trait:
```rust
fn from_signature_private_to_public(
    private_key: &Self::SignaturePrivateKey
) -> Result<Self::SignaturePublicKey, CryptoError>;
```

Implement in `ClassicSuiteProvider`:
```rust
fn from_signature_private_to_public(
    private_key: &Self::SignaturePrivateKey
) -> Result<Self::SignaturePublicKey, CryptoError> {
    let bytes_slice: &[u8] = private_key.as_ref();
    let bytes: &[u8; 32] = bytes_slice
        .try_into()
        .map_err(|_| CryptoError::InvalidInputError("Invalid signing key length".to_string()))?;
    let signing_key = SigningKey::from_bytes(bytes);
    let verifying_key = signing_key.verifying_key();
    Ok(verifying_key.to_bytes().to_vec())
}
```

---

### 4. **Excessive Debug Logging with `eprintln!`**

**Location**: Throughout crypto modules

**Issue**: 45+ `eprintln!` calls in production code

**Impact**: 🟡 **MEDIUM**
- Performance overhead
- Leaks sensitive information to stderr
- Not configurable logging

**Examples**:
```rust
eprintln!("[X3DH] perform_x3dh called");
eprintln!("[X3DH] remote_signature length: {}", remote_signature.len());
eprintln!("[DoubleRatchet] decrypt: msgNum={}", encrypted.message_number);
```

**Recommendation**:
Replace all `eprintln!` with proper `tracing` crate:
```rust
use tracing::{debug, trace};

debug!(target: "crypto::x3dh", "perform_x3dh called");
trace!(remote_signature_len = %remote_signature.len());
```

---

## 🟢 Good Practices Observed

### ✅ **1. Zero Unsafe Code**

The entire cryptographic core contains **0 unsafe blocks**. This is excellent for memory safety.

**Benefit**:
- Rust's ownership system prevents memory corruption
- UniFFI handles FFI boundary safely
- No manual memory management errors

---

### ✅ **2. Crypto-Agility Architecture**

The `CryptoProvider` trait enables algorithm agility:

```rust
pub trait CryptoProvider: Send + Sync + 'static {
    type KemPublicKey: AsRef<[u8]> + Debug + Clone + 'static;
    type KemPrivateKey: AsRef<[u8]> + Debug + Clone + 'static;
    // ...
}
```

**Benefits**:
- Easy to add PQ algorithms
- Suite negotiation supported
- Clean abstraction

---

### ✅ **3. Double Ratchet: Out-of-Order Message Handling**

Correctly implements skipped message key storage:

```rust
const MAX_SKIPPED_MESSAGES: u32 = 1000;

// Store skipped keys
self.skipped_message_keys.insert(self.receiving_chain_length, msg_key);

// DoS protection
if self.skipped_message_keys.len() > MAX_SKIPPED_MESSAGES as usize {
    return Err("Too many skipped messages".to_string());
}
```

**Test Result**: ✅ PASSED
```
test test_double_ratchet_out_of_order_messages ... ok
```

---

### ✅ **4. Proper Nonce Generation**

Uses OS random number generator:

```rust
fn generate_nonce(len: usize) -> Result<Vec<u8>, CryptoError> {
    let mut nonce_bytes = vec![0u8; len];
    OsRng.fill_bytes(&mut nonce_bytes);
    Ok(nonce_bytes)
}
```

**Test Result**: ✅ PASSED (100 unique nonces generated)

---

## 📊 Test Results

### Test Coverage Report

**Total Tests**: 21
**Passed**: 16 (76%)
**Failed**: 5 (24%)

#### ✅ Passing Tests (16/21)

| Test Name | Category | Result |
|-----------|----------|--------|
| `test_classic_suite_generate_kem_keys` | KeyGen | ✅ PASS |
| `test_classic_suite_generate_signature_keys` | KeyGen | ✅ PASS |
| `test_classic_suite_sign_verify` | Signatures | ✅ PASS |
| `test_classic_suite_verify_fails_with_wrong_message` | Signatures | ✅ PASS |
| `test_classic_suite_aead_encrypt_decrypt` | AEAD | ✅ PASS |
| `test_classic_suite_aead_decrypt_fails_with_wrong_key` | AEAD | ✅ PASS |
| `test_classic_suite_aead_decrypt_fails_with_wrong_nonce` | AEAD | ✅ PASS |
| `test_classic_suite_hkdf` | KDF | ✅ PASS |
| `test_classic_suite_kdf_rk` | KDF | ✅ PASS |
| `test_classic_suite_kdf_ck` | KDF | ✅ PASS |
| `test_x3dh_perform_handshake` | X3DH | ✅ PASS |
| `test_x3dh_fails_with_invalid_signature` | X3DH | ✅ PASS |
| `test_double_ratchet_initiator_session` | Double Ratchet | ✅ PASS |
| `test_double_ratchet_full_roundtrip` | Double Ratchet | ✅ PASS |
| `test_double_ratchet_out_of_order_messages` | Double Ratchet | ✅ PASS |
| `test_random_number_quality` | RNG | ✅ PASS |

#### ❌ Failing Tests (5/21)

All failures caused by **Critical Finding #1** (verifying key bug):

| Test Name | Error | Root Cause |
|-----------|-------|-----------|
| `test_client_crypto_registration_bundle` | Signature verification failed | Invalid verifying key |
| `test_client_crypto_init_session` | Signature verification failed | Invalid verifying key |
| `test_client_crypto_message_exchange` | Signature verification failed | Invalid verifying key |
| `test_encryption_performance` | Signature verification failed | Invalid verifying key |
| `test_session_serialization` | Signature verification failed | Invalid verifying key |

---

## 🔬 Detailed Technical Analysis

### Double Ratchet Implementation Review

**Strengths**:
1. ✅ Correct ratchet step logic
2. ✅ Proper DH ratchet on new ephemeral keys
3. ✅ Chain key derivation (KDF_CK) correct
4. ✅ Root key derivation (KDF_RK) correct
5. ✅ Skipped message handling with DoS protection

**Issues**:
1. ⚠️ No timestamp tracking for skipped messages (defined but unused)
2. ⚠️ No cleanup of old skipped keys

**Recommendation**:
Implement periodic cleanup:
```rust
pub fn cleanup_old_skipped_keys(&mut self, max_age_seconds: i64) {
    let now = current_timestamp();
    self.skipped_message_keys.retain(|msg_num, _| {
        if let Some(&timestamp) = self.skipped_key_timestamps.get(msg_num) {
            (now - timestamp as i64) < max_age_seconds
        } else {
            false // Remove keys without timestamps
        }
    });
}
```

---

### X3DH Implementation Review

**Current Implementation**:
```rust
pub fn perform_x3dh(
    identity_private: &P::KemPrivateKey,
    _signed_prekey_private: &P::KemPrivateKey, // ⚠️ UNUSED
    remote_identity_public: &P::KemPublicKey,
    remote_signed_prekey_public: &P::KemPublicKey,
    remote_signature: &[u8],
    remote_verifying_key: &P::SignaturePublicKey,
    _remote_suite_id: SuiteID, // ⚠️ UNUSED
) -> Result<Vec<u8>, String>
```

**Issues**:
1. ⚠️ Simplified X3DH (no ephemeral keys)
2. ⚠️ No one-time prekey support
3. ⚠️ `signed_prekey_private` parameter accepted but unused

**Signal Protocol X3DH** requires:
- DH1 = DH(IK_A, SPK_B)
- DH2 = DH(EK_A, IK_B)
- DH3 = DH(EK_A, SPK_B)
- DH4 = DH(EK_A, OPK_B) [optional]

**Current implementation** only does:
- DH1 = DH(IK_A, IK_B)

**Recommendation**:
Either:
1. Complete full X3DH implementation, OR
2. Document this as "X3DH-Lite" and ensure security review

---

### AEAD Implementation Review

**ChaCha20-Poly1305 Usage**:
```rust
fn aead_encrypt(
    key: &Self::AeadKey,
    nonce: &[u8],
    plaintext: &[u8],
    associated_data: Option<&[u8]>,
) -> Result<Vec<u8>, CryptoError>
```

**Strengths**:
1. ✅ Correct nonce size (12 bytes)
2. ✅ Tag included in ciphertext
3. ✅ Proper error handling
4. ✅ Associated data support

**Concerns**:
1. ⚠️ Nonce reuse protection relies on Double Ratchet (acceptable)
2. ⚠️ No explicit nonce counter tracking

**Test Result**: All AEAD tests ✅ PASSED

---

## 🛡️ Security Recommendations

### Immediate (Critical)

1. ✅ **Fix verifying key generation** (Critical Finding #1)
2. ✅ **Add signature key derivation** to CryptoProvider trait
3. ✅ **Run all tests** and ensure 100% pass rate
4. ✅ **Remove or fix PQ code** (compilation errors)

### Short-term (1-2 weeks)

1. 🔧 Replace `eprintln!` with `tracing` crate
2. 🔧 Add comprehensive test coverage (target: ≥90%)
3. 🔧 Implement skipped message cleanup
4. 🔧 Add integration tests for Swift↔Rust boundary
5. 🔧 Document X3DH-Lite vs full X3DH

### Medium-term (1-2 months)

1. 📚 Complete or remove PQ implementation
2. 📚 Add fuzz testing for crypto functions
3. 📚 External security audit by crypto experts
4. 📚 Implement key rotation mechanism
5. 📚 Add session persistence to avoid re-init

---

## 📋 Test Suite Created

Created comprehensive test file: `packages/core/tests/crypto_tests.rs`

**Test Categories**:
- ✅ Key Generation (KEM, Signatures)
- ✅ Signature Operations (Sign, Verify, Failure cases)
- ✅ AEAD Encryption/Decryption (Success, Wrong key, Wrong nonce)
- ✅ Key Derivation (HKDF, KDF_RK, KDF_CK)
- ✅ X3DH Protocol (Success, Invalid signature)
- ✅ Double Ratchet (Initiator, Receiver, Full roundtrip, Out-of-order)
- ✅ ClientCrypto (Registration, Session init, Message exchange) - **Currently failing**
- ✅ Session Serialization
- ✅ Performance Benchmarks
- ✅ RNG Quality

**To Run Tests**:
```bash
cd packages/core
cargo test --test crypto_tests
```

---

## 📈 Code Quality Metrics

| Metric | Score | Target | Status |
|--------|-------|--------|--------|
| Memory Safety | 10/10 | 10/10 | ✅ |
| Test Coverage | ~40% | 90% | ❌ |
| Unsafe Blocks | 0 | 0 | ✅ |
| Critical Bugs | 1 | 0 | ❌ |
| High Priority Issues | 3 | 0 | ⚠️ |
| Documentation | 6/10 | 9/10 | ⚠️ |

---

## 🎯 Conclusions

### What Works Well

1. ✅ **Memory safety**: Zero unsafe code
2. ✅ **Architecture**: Clean crypto-agility design
3. ✅ **Double Ratchet**: Core protocol correct
4. ✅ **Primitives**: ChaCha20-Poly1305, Ed25519, X25519 properly used
5. ✅ **UniFFI Integration**: Clean FFI boundary

### Critical Blockers

1. ❌ **Verifying key bug** breaks ALL client operations
2. ❌ **No test coverage** before this audit
3. ❌ **PQ code incomplete** and non-functional

### Verdict

**DO NOT DEPLOY** to production until:
1. Critical Finding #1 is fixed
2. All 21 tests pass
3. Code review by another developer
4. Manual E2E testing with iOS client

**Estimated time to production-ready**: 1-2 weeks of focused development.

---

## 📞 Contact

For questions about this audit report, contact the development team or refer to:
- `docs/TESTING.md` - Testing guidelines
- `docs/ROADMAP.md` - Development roadmap
- `docs/ARCHITECTURE_RESPONSIBILITY.md` - Code architecture

---

**Report Generated**: December 27, 2025
**Next Audit Recommended**: After critical bugs are fixed
**Audit Tool**: Claude Sonnet 4.5 with comprehensive test suite
