#! /usr/bin/env bash
set -eou pipefail

# This wrapper script is used because the C#/F# compilers both embed absolute paths
# into their outputs and those paths are not deterministic. The compilers also
# allow overriding these paths using pathmaps. Since the paths can not be known
# at analysis time we need to override them at execution time.

# The ICU the build carries, if any: the runtime looks the libraries up by name,
# so their directory goes on the loader's path.
if [[ "${1:-}" == --icu=* ]]; then
  export LD_LIBRARY_PATH="$PWD/$(dirname "${1#--icu=}")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  shift
fi

COMPILER="$2"
PATHMAP_FLAG="-pathmap"

# Needed because unfortunately the F# compiler uses a different flag name
if [[ $(basename "$COMPILER") == "fsc.dll" ]]; then
  PATHMAP_FLAG="--pathmap"
fi
PATHMAP="$PATHMAP_FLAG:$PWD=."

# fsc also records full paths where its pathmap does not reach: the source
# location of a quotation literal, the location a MatchFailureException reports,
# and the room the debug directory reserves for the PDB path. So on Linux it gets
# its paths under /proc/self/cwd, which names the working directory the same way
# in every execution root, and its diagnostics get them back relative. The F#
# compiler worker does the same in StableSourceRoot.cs.
STABLE_ROOT=/proc/self/cwd
if [[ $(basename "$COMPILER") == "fsc.dll" && $(uname) == Linux && -d "$STABLE_ROOT" ]]; then
  response_files="$(mktemp -d)"
  trap 'rm -rf "$response_files"' EXIT

  stable_args=()
  for arg in "${@:3}"; do
    if [[ "$arg" == @* ]]; then
      response_file="$response_files/${#stable_args[@]}.rsp"
      awk -v root="$STABLE_ROOT" '
        function under(path) { return (path == "" || substr(path, 1, 1) == "/") ? path : root "/" path }
        !/^-/ { print under($0); next }
        match($0, /^--?[A-Za-z]+:/) {
          flag = substr($0, 1, RLENGTH); value = substr($0, RLENGTH + 1)
          name = tolower(flag); gsub(/[-:]/, "", name)
          if (name == "out" || name == "o" || name == "pdb" || name == "refout") { print flag under(value); next }
          if (name == "embed") {
            rooted = ""
            while (match(value, /[,;]/)) { rooted = rooted under(substr(value, 1, RSTART - 1)) substr(value, RSTART, 1); value = substr(value, RSTART + 1) }
            print flag rooted under(value); next
          }
        }
        { print }
      ' "${arg#@}" >"$response_file"
      stable_args+=("@$response_file")
    else
      stable_args+=("$arg")
    fi
  done

  ./"$1" "$2" "${stable_args[@]}" "$PATHMAP" "--pathmap:$STABLE_ROOT=." 2>&1 | sed "s|$STABLE_ROOT/||g"
  exit
fi

# shellcheck disable=SC2145
./"$@" "$PATHMAP"
