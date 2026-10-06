#!/usr/bin/env bash
# One-time: wire https://ai.duk-tech.com/books-api/ to the API. Needs sudo.
# Adds a single include line to the existing site, tests the config, and only
# then reloads nginx. Re-running is safe.
set -euo pipefail
conf=/etc/nginx/sites-enabled/ai.duk-tech.com.conf
inc="include $(cd "$(dirname "$0")" && pwd)/nginx-books-api.conf;"

if grep -qF "$inc" "$conf"; then
  echo "already wired"
else
  sudo cp "$conf" "$conf.bak-books-api"
  # Insert right after the `server_name` line, inside the server block.
  sudo sed -i "0,/server_name ai.duk-tech.com;/s||server_name ai.duk-tech.com;\n\n    $inc|" "$conf"
fi

if sudo nginx -t; then
  sudo systemctl reload nginx
  echo "reloaded. Try: curl https://ai.duk-tech.com/books-api/healthz"
else
  echo "nginx -t failed; restoring the previous config" >&2
  sudo cp "$conf.bak-books-api" "$conf"
  exit 1
fi
