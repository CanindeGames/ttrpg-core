#!/usr/bin/env sh
# Developer task runner. Works in Git Bash (Windows), Linux and macOS.
#
#   scripts/dev.sh setup        install busted/luacheck/luacov into ./.luarocks
#   scripts/dev.sh test [args]  run the test suite (args go to busted)
#   scripts/dev.sh lint         luacheck
#   scripts/dev.sh fmt          format with StyLua
#   scripts/dev.sh fmt-check    verify formatting
#   scripts/dev.sh cov          tests with coverage -> luacov.report.out
#   scripts/dev.sh check        lint + fmt-check + test (what CI runs)
set -eu
cd "$(dirname "$0")/.."

TREE=.luarocks
LUA_DIRS="src spec examples"

# Finds a tool in the project tree (.bat wrappers on Windows), then on PATH.
resolve() {
    for candidate in "$TREE/bin/$1" "$TREE/bin/$1.bat"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    if command -v "$1" >/dev/null 2>&1; then
        command -v "$1"
        return 0
    fi
    echo "error: '$1' not found - run: scripts/dev.sh setup" >&2
    return 1
}

run_stylua() {
    if command -v stylua >/dev/null 2>&1; then
        command stylua "$@"
    else
        npx --yes @johnnymorganz/stylua-bin "$@"
    fi
}

cmd=${1:-check}
[ $# -gt 0 ] && shift

case "$cmd" in
    setup)
        for rock in busted luacheck luacov; do
            luarocks --tree "$TREE" install "$rock"
        done
        ;;
    test)
        "$(resolve busted)" "$@"
        ;;
    lint)
        "$(resolve luacheck)" $LUA_DIRS
        ;;
    fmt)
        run_stylua $LUA_DIRS
        ;;
    fmt-check)
        run_stylua --check $LUA_DIRS
        ;;
    cov)
        rm -f luacov.stats.out luacov.report.out
        "$(resolve busted)" --coverage "$@"
        "$(resolve luacov)"
        # Summary table is at the end of the report.
        sed -n '/^Summary/,$p' luacov.report.out
        ;;
    check)
        "$0" lint
        "$0" fmt-check
        "$0" test
        ;;
    *)
        sed -n '2,11p' "$0"
        exit 1
        ;;
esac
