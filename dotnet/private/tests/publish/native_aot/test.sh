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

tar -xvf "$1"

# A NativeAOT publish is one native executable: no apphost, no managed
# assemblies, and no runtimeconfig.json telling a runtime how to start.
for unwanted in app_to_publish.dll app_to_publish.runtimeconfig.json app_to_publish.deps.json; do
    if [[ -f "./$unwanted" ]]; then
        echo "NativeAOT publish should not contain $unwanted"
        exit 1
    fi
done

./app_to_publish
