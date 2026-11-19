#! /usr/bin/env bash

set -eou pipefail

# The tar has to hold the published files, not symlinks into Bazel's output
# tree, which a publish filled with symlinks would otherwise carry along.
bash ./dotnet/private/tests/publish/expect_no_symlinks.sh "$1"

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    tar -xvf "$1"
    ./app_to_publish
elif [[ "$OSTYPE" == "darwin"* ]]; then
    tar -xvf "$1"
    ./app_to_publish
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    tar -xvf "$1"
    ./app_to_publish.exe
else
    echo "Could not figure out which OS is running the test"
    exit 1
fi

