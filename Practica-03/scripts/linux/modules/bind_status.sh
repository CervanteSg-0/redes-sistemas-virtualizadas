#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MOD_DIR/common.sh"

service_status() {
  systemctl --no-pager -l status named || true
  show_listen_53
}