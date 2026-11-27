#! /usr/bin/env bash

# Unpacks a publish that left its dependencies in its runfiles tree, and runs
# it the way it runs once deployed: from another directory, with none of
# Bazel's runfiles variables set, so that the .NET host can only find the
# dependencies through the runfiles tree beside the executable.
#
# Usage: test.sh <tar> <dotnet>

set -eou pipefail

tar="$PWD/$1"

# A framework-dependent publish runs on the toolchain's runtime.
toolchain="../${2#external/}"
DOTNET_ROOT="$(cd "$(dirname "$toolchain")" && pwd)"
export DOTNET_ROOT

unset RUNFILES_DIR JAVA_RUNFILES RUNFILES_MANIFEST_FILE RUNFILES_MANIFEST_ONLY

deployed="${TEST_TMPDIR}/deployed"
mkdir -p "$deployed"
tar -xf "$tar" -C "$deployed"

# Only what has to be beside the executable was copied beside it.
beside=$(find "$deployed" -maxdepth 1 \( -iname "*LibGit2Sharp*" -o -iname "*CoreLib*" \))
if [[ -n "$beside" ]]; then
    echo "$beside"
    echo "Dependencies were published beside the executable rather than left in the runfiles tree"
    exit 1
fi

cd "$TEST_TMPDIR"

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    "$deployed/app_to_publish.exe"
else
    "$deployed/app_to_publish"
fi
