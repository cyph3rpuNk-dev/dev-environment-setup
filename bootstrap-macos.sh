#!/usr/bin/env bash
# macOS entry point. bootstrap-linux.sh detects macOS and uses Homebrew; this name
# exists so Mac users can find the right script. All options are passed through.
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/bootstrap-linux.sh" "$@"
