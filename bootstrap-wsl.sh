#!/usr/bin/env bash
# Compatibility entry point. bootstrap-linux.sh now supports native Linux and WSL;
# this name is kept so existing instructions and habits keep working.
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/bootstrap-linux.sh" "$@"
