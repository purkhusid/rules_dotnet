#! /usr/bin/env bash

# Runs a publish where Bazel leaves it, the way `bazel run` or a path into
# bazel-bin does, rather than out of a tar.
#
# Only there does a publish of symlinks keep its links: a tar or an image layer
# holds the files they point to. The apphost finds the application's directory
# from the real path of the assembly it starts, so this is where that assembly
# being a link rather than a file would show.
#
# Usage: run_in_place.sh <publish executable> [<dotnet executable>]
#
# The dotnet executable is the toolchain's, which a framework-dependent
# publish runs on.

set -eou pipefail

if [[ $# -gt 1 ]]; then
    TOOLCHAIN_LOCATION=$(dirname "$2")
    DOTNET_ROOT="../${TOOLCHAIN_LOCATION#'external/'}/"
    export DOTNET_ROOT
fi

"$1"
