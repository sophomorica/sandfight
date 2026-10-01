#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  echo "WARNING: no .env at the repo root. SENTRY_DSN is unset." >&2
fi

if [[ -z "${SENTRY_DSN:-}" ]]; then
  echo "WARNING: SENTRY_DSN is empty. This IPA will not send crashes or sessions." >&2
fi

version="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
exec flutter build ipa \
  --dart-define="SENTRY_DSN=${SENTRY_DSN:-}" \
  --dart-define="APP_RELEASE=sandfight@${version}"
