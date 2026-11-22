#!/usr/bin/env bash
# scripts/tests/check-injected-js.sh
# Validates all JavaScript files and inline wrapper <script> tags with `node --check`
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)"

FAILED=0

# 1. Validate static assets/np-theme.js if present
if [ -f "$REPO_ROOT/assets/np-theme.js" ]; then
    echo "Checking syntax: assets/np-theme.js..."
    if ! node --check "$REPO_ROOT/assets/np-theme.js"; then
        echo "✖ Syntax error in assets/np-theme.js" >&2
        FAILED=1
    else
        echo "✔ assets/np-theme.js syntax OK"
    fi
fi

# 2. If a wrapper file is passed as an argument or exists in target panel, validate inline scripts
WRAPPER_FILE="${1:-}"
if [ -n "$WRAPPER_FILE" ] && [ -f "$WRAPPER_FILE" ]; then
    echo "Extracting and checking inline <script> blocks from $WRAPPER_FILE..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # Use node to extract and check inline scripts without src attribute
    node -e '
        const fs = require("fs");
        const path = require("path");
        const file = process.argv[1];
        const tmpDir = process.argv[2];
        const content = fs.readFileSync(file, "utf-8");
        const regex = /<script(?![^>]*\bsrc\b)[^>]*>([\s\S]*?)<\/script>/gi;
        let match;
        let idx = 0;
        let hasErrors = false;

        while ((match = regex.exec(content)) !== null) {
            idx++;
            const jsCode = match[1].trim();
            if (!jsCode) continue;
            const scriptPath = path.join(tmpDir, `inline_${idx}.js`);
            fs.writeFileSync(scriptPath, jsCode, "utf-8");
            try {
                require("child_process").execSync(`node --check "${scriptPath}"`, { stdio: "pipe" });
                console.log(`  ✔ Inline script #${idx} syntax OK`);
            } catch (err) {
                console.error(`  ✖ Inline script #${idx} syntax error:`, err.stderr ? err.stderr.toString() : err.message);
                hasErrors = true;
            }
        }
        if (hasErrors) process.exit(1);
    ' "$WRAPPER_FILE" "$TMP_DIR" || FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "❌ JavaScript syntax check failed!" >&2
    exit 1
fi

echo "✅ All JavaScript syntax checks passed successfully."
exit 0
