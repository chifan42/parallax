#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building daemon..."
cargo build

echo "Starting daemon..."
RUST_LOG=parallax_daemon=debug ./target/debug/parallax-daemon
