#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

validate_named() {
  echo "== Validacion (named-checkconf) =="
  named-checkconf && echo "[OK] named-checkconf OK" || die "named-checkconf fallo"
}
