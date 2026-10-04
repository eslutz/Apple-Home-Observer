#!/bin/bash
# Local trusted operator configuration; never distributed with the app.
config_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$config_root/Config/deployment.env" ]]; then source "$config_root/Config/deployment.env"; fi
: "${OBSERVER_DEPLOY_HOST:?Set OBSERVER_DEPLOY_HOST or Config/deployment.env}"
: "${OBSERVER_BUNDLE_ID:?Set OBSERVER_BUNDLE_ID or Config/deployment.env}"
[[ "$OBSERVER_DEPLOY_HOST" != -* && "$OBSERVER_DEPLOY_HOST" =~ ^[a-zA-Z0-9@._-]+$ ]] || exit 2
[[ "$OBSERVER_BUNDLE_ID" =~ ^[a-zA-Z0-9.-]+$ ]] || exit 2
target="$OBSERVER_DEPLOY_HOST"
