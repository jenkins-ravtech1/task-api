#!/usr/bin/env bash
# Create a couple of tasks against a running Tasks API (PRD §7).
# Usage: scripts/local-seed.sh [base-url]   (default http://localhost:8080)
set -euo pipefail

BASE="${1:-http://localhost:8080}"

for title in "Learn Docker" "Write Terraform" "Ship to AWS"; do
  echo "Creating task: ${title}"
  curl -s -X POST "${BASE}/tasks" \
    -H 'Content-Type: application/json' \
    -d "{\"title\":\"${title}\"}"
  echo
done

echo
echo "All tasks:"
curl -s "${BASE}/tasks"
echo
