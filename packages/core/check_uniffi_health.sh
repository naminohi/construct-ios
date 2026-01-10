#!/bin/bash
# UniFFI Health Check Script
# Проверяет корректность настройки UniFFI в проекте

set -e

echo "🔍 UniFFI Health Check"
echo "====================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Check Rust uniffi version
echo "📦 Checking Rust uniffi version..."
RUST_UNIFFI_VERSION=$(cargo tree -i uniffi 2>/dev/null | grep "uniffi v" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "NOT FOUND")
if [ "$RUST_UNIFFI_VERSION" != "NOT FOUND" ]; then
    echo -e "${GREEN}✓${NC} Rust uniffi: $RUST_UNIFFI_VERSION"
else
    echo -e "${RED}✗${NC} Rust uniffi: NOT FOUND"
fi
echo ""

# 2. Check Python uniffi-bindgen version
echo "🐍 Checking Python uniffi-bindgen version..."
if command -v uniffi-bindgen &> /dev/null; then
    PYTHON_UNIFFI_VERSION=$(uniffi-bindgen --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "UNKNOWN")
    echo -e "${GREEN}✓${NC} Python uniffi-bindgen: $PYTHON_UNIFFI_VERSION"
else
    echo -e "${RED}✗${NC} Python uniffi-bindgen: NOT INSTALLED"
fi
echo ""

# 3. Check version compatibility
echo "🔗 Checking version compatibility..."
if [ "$RUST_UNIFFI_VERSION" == "$PYTHON_UNIFFI_VERSION" ]; then
    echo -e "${GREEN}✓${NC} Versions match: $RUST_UNIFFI_VERSION"
elif [ "$RUST_UNIFFI_VERSION" != "NOT FOUND" ] && [ "$PYTHON_UNIFFI_VERSION" != "UNKNOWN" ]; then
    echo -e "${YELLOW}⚠${NC} Version mismatch:"
    echo "  Rust:   $RUST_UNIFFI_VERSION"
    echo "  Python: $PYTHON_UNIFFI_VERSION"
    echo "  This may cause compatibility issues!"
else
    echo -e "${RED}✗${NC} Cannot check compatibility (missing tools)"
fi
echo ""

# 4. Check build.rs patching
echo "🔧 Checking build.rs patching..."
if grep -q "patch_uniffi_file" build.rs 2>/dev/null; then
    echo -e "${GREEN}✓${NC} build.rs patching enabled (needed for Rust 1.82+)"
else
    echo -e "${YELLOW}⚠${NC} build.rs patching not found"
fi
echo ""

# 5. Test Rust build
echo "🦀 Testing Rust build..."
if cargo check --lib > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Rust library builds successfully"
else
    echo -e "${RED}✗${NC} Rust build FAILED"
    echo "Run: cargo build --lib"
fi
echo ""

# 6. Test Swift bindings generation
echo "🍎 Testing Swift bindings generation..."
TEMP_DIR=$(mktemp -d)
if uniffi-bindgen generate --language swift src/construct_core.udl --out-dir "$TEMP_DIR" > /dev/null 2>&1; then
    SWIFT_SIZE=$(ls -lh "$TEMP_DIR/construct_core.swift" 2>/dev/null | awk '{print $5}')
    echo -e "${GREEN}✓${NC} Swift bindings generated successfully ($SWIFT_SIZE)"
    rm -rf "$TEMP_DIR"
else
    echo -e "${RED}✗${NC} Swift generation FAILED"
    rm -rf "$TEMP_DIR"
fi
echo ""

# 7. Check Rust version
echo "🔨 Checking Rust version..."
RUST_VERSION=$(rustc --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "  Current: $RUST_VERSION"
if [[ "$RUST_VERSION" > "1.82" ]] || [[ "$RUST_VERSION" == "1.82"* ]]; then
    echo -e "${YELLOW}⚠${NC} Rust 1.82+ detected - build.rs patching is REQUIRED"
else
    echo -e "${GREEN}✓${NC} Rust version OK"
fi
echo ""

# 8. Summary
echo "📊 Summary"
echo "=========="
if [ "$RUST_UNIFFI_VERSION" == "$PYTHON_UNIFFI_VERSION" ] && \
   cargo check --lib > /dev/null 2>&1; then
    echo -e "${GREEN}✓ All systems operational!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some issues detected. Check output above.${NC}"
    echo ""
    echo "💡 Recommendations:"
    echo "  1. Read UNIFFI_VERSION_GUIDE.md for detailed info"
    echo "  2. Ensure Python uniffi-bindgen is installed: pip3 install uniffi-bindgen"
    echo "  3. Keep versions in sync"
    exit 1
fi
