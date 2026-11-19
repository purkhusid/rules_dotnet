#! /usr/bin/env bash

set -eou pipefail

# The tar has to hold the published files, not symlinks into Bazel's output
# tree, which a publish filled with symlinks would otherwise carry along.
bash ./dotnet/private/tests/publish/expect_no_symlinks.sh "$2"

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

TOOLCHAIN_LOCATION=$(dirname "$1")
DOTNET_ROOT="../${TOOLCHAIN_LOCATION#'external/'}/"
export DOTNET_ROOT

tar -xf "$2"

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ./app_to_publish.exe
else
    ./app_to_publish
fi
