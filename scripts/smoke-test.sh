#!/usr/bin/env bash
# =============================================================================
# Smoke test (PRD §16, §14.2). Used by CD after a deploy, and runnable by hand.
#
# Polls /health until the service is up (the instance may still be pulling the
# new image), then creates a task and reads it back. Exits non-zero on any
# failure so CD can fail the deploy.
#
# Usage: scripts/smoke-test.sh <base-url>
#   e.g. scripts/smoke-test.sh http://localhost:8080
# =============================================================================
set -euo pipefail

BASE="${1:?usage: smoke-test.sh <base-url>}"
echo "Smoke test against ${BASE}"

# 1. Wait for /health to return 200.
healthy=false
for i in $(seq 1 30); do
  if curl -fsS "${BASE}/health" >/dev/null 2>&1; then
    healthy=true
    echo "health OK"
    break
  fi
  echo "waiting for /health (${i}/30)..."
  sleep 10
done
if [ "${healthy}" != "true" ]; then
  echo "FAILED: /health never returned 200"
  exit 1
fi

# 2. Create a task → expect a body with an id.
created=$(curl -fsS -X POST "${BASE}/tasks" \
  -H 'Content-Type: application/json' \
  -d '{"title":"smoke-test"}')
echo "created: ${created}"

# Extract the id without needing jq.
id=$(printf '%s' "${created}" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
if [ -z "${id}" ]; then
  echo "FAILED: no id in create response"
  exit 1
fi

# 3. Read it back → expect 200.
curl -fsS "${BASE}/tasks/${id}" >/dev/null
echo "read back OK (${id})"

echo "SMOKE TEST PASSED"
