#!/usr/bin/env bash
# dev-environment-setup browser bridge v2
# URLs are base64-encoded data on stdin, never interpolated into PowerShell code.
set -euo pipefail
if [ "$#" -ne 1 ]; then
  echo 'usage: wslview <http-or-https-url>' >&2
  exit 2
fi
case "$1" in
  http://*|https://*) ;;
  *) echo 'Only http and https URLs are supported.' >&2; exit 2 ;;
esac
printf '%s' "$1" | base64 | /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -NoProfile -NonInteractive -Command '
$ErrorActionPreference = "Stop"
$url = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([Console]::In.ReadToEnd()))
$uri = $null
if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @("http", "https")) {
    throw "Only absolute http and https URLs are supported."
}
Start-Process -FilePath $uri.AbsoluteUri
'
