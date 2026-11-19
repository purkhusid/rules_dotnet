"""Runs a publish test against each way a publish can fill its directory."""

# The `file_mode` of each variant of a publish under test, keyed by the suffix
# of the variant's targets. The first leaves it unset, so that the
# `publish_file_mode` flag decides; the second symlinks, which has to work as
# well once a packaging rule has packed the publish and it runs outside of
# Bazel.
FILE_MODES = {
    "": None,
    "_symlink": "symlink",
}

_PLATFORM_RIDS = {
    "//dotnet/private:linux-arm64": "linux-arm64",
    "//dotnet/private:linux-x64": "linux-x64",
    "//dotnet/private:osx-arm64": "osx-arm64",
    "//dotnet/private:osx-x64": "osx-x64",
    "//dotnet/private:windows-arm64": "win-arm64",
    "//dotnet/private:windows-x64": "win-x64",
}

def publish_directory(publish, subdirectory = "publish", windows = True):
    """The directory of a publish for the platform being built for.

    For the `strip_prefix` of a `pkg_tar` that puts the publish at the root of
    the tar, which keeps paths short enough for Windows.

    Args:
        publish: The name of the publish_binary target.
        subdirectory: Where under the target's name the publish lands: `aot`
            for a NativeAOT one.
        windows: Whether the publish can be built for Windows at all.

    Returns:
        A select of the directory's path, relative to the package.
    """
    return select({
        setting: "{}/{}/{}".format(publish, subdirectory, rid)
        for (setting, rid) in _PLATFORM_RIDS.items()
        if windows or not rid.startswith("win-")
    })
