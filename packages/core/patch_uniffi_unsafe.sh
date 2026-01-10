#!/bin/bash
# Patch UniFFI generated code to work with Rust 1.82+
# This script wraps #[no_mangle] attributes in unsafe(...)

set -e

# Find the generated uniffi file
UNIFFI_FILE=$(find target/debug/build -name "construct_core.uniffi.rs" 2>/dev/null | head -1)

if [ -z "$UNIFFI_FILE" ]; then
    echo "Warning: UniFFI generated file not found. Run 'cargo build' first."
    exit 0
fi

echo "Patching UniFFI file: $UNIFFI_FILE"

# Replace #[no_mangle] with #[unsafe(no_mangle)]
sed -i.bak 's/#\[no_mangle\]/#[unsafe(no_mangle)]/g' "$UNIFFI_FILE"

# Replace #[export_name = "..."] with #[unsafe(export_name = "...")]
sed -i.bak 's/#\[export_name =/#[unsafe(export_name =/g' "$UNIFFI_FILE"

echo "Patch applied successfully!"
rm -f "${UNIFFI_FILE}.bak"
