#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
cargo build --release

echo "Built: target/release/parallax-daemon"
