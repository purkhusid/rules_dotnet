#! /usr/bin/env bash

# Fails if an archive holds a symlink rather than the file it links to.
#
# A publish filled with symlinks has to reach a tar or an image layer as the
# files its links point to. A link would lead back into Bazel's output tree,
# which only exists on the machine that built it. It would still resolve there,
# so running the extracted application would not notice.
#
# Usage: expect_no_symlinks.sh <archive>...

set -eou pipefail

status=0

for archive in "$@"; do
    # Listed the way `ls -l` lists files, a symlink's line starts with an `l`.
    # tar reads a compressed archive as readily as a plain one.
    links=$(tar -tvf "$archive" | grep '^l' || true)

    if [[ -n "$links" ]]; then
        echo "$archive holds symlinks rather than the files they link to:"
        echo "$links"
        status=1
    fi
done

exit "$status"
