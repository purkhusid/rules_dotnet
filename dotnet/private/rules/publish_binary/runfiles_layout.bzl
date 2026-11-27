"""Points a publish's deps.json at its runfiles tree instead of the publish directory.

A publish lays its files out in a directory, and its deps.json tells the .NET
host where each one is. With `dependencies_in_runfiles`, the files the deps.json
lists stay where Bazel puts them, in the runfiles tree beside the executable,
and each asset's `localPath` says where that is relative to the application's
directory. Only what has to be in the application's directory is copied there.

The host of .NET 10 and later reads `localPath`, in a framework-dependent
deps.json as in a self-contained one. An application runs on the runtime of the
framework it is built for or a later one, so a binary built for .NET 10 or
later always has such a host.

The host anchors the paths at the application's directory, which it finds by
resolving the executable's symlinks. The runfiles tree has to be beside it
there, as Bazel lays it out and as packaging rules carry it.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//dotnet/private:common.bzl", "to_rlocation_path")

# The first version whose host reads `localPath`.
LOCAL_PATH_MIN_MAJOR_VERSION = 10

# The sections of a deps.json target that list assets, each keyed by the
# asset's path inside the publish directory.
_ASSET_SECTIONS = ["runtime", "native", "resources", "runtimeTargets"]

# The host libraries a self-contained executable loads from beside itself.
_HOST_LIBRARIES = ["hostfxr", "hostpolicy"]

def host_libraries(runtime_pack_files):
    """The publish paths of the host libraries a self-contained executable loads from beside itself.

    Args:
        runtime_pack_files: The files each runtime pack contributes, as structs of `native`.

    Returns:
        A list of publish paths.
    """
    return [
        file.basename
        for pack in runtime_pack_files
        for file in pack.native
        if paths.split_extension(file.basename)[0].removeprefix("lib") in _HOST_LIBRARIES
    ]

def _locate(entries, key, runtime_identifier):
    """The publish path and File a deps.json asset key stands for, or None.

    A native library built in this workspace is listed by its name, but laid
    out under `runtimes/<rid>/native/` in a framework-dependent publish.
    """
    for path in [key, "runtimes/{}/native/{}".format(runtime_identifier, key)]:
        if path in entries:
            return (path, entries[path])

    return None

def relocate_to_runfiles(ctx, depsjson, entries, executable, runtime_identifier, beside):
    """Rewrites a publish's deps.json to give each asset the `localPath` of its runfile.

    Args:
        ctx: The rule context.
        depsjson: The deps.json, from `generate_depsjson`, describing `entries`.
        entries: The File each path of the publish directory would hold.
        executable: The publish's executable, beside which the runfiles tree is.
        runtime_identifier: The runtime identifier the publish lays native libraries out for.
        beside: The publish paths that stay in the application's directory even
            though the deps.json lists them.

    Returns:
        A struct of the rewritten `depsjson`, and `relocated`: the File of each
        publish path left in the runfiles tree.
    """
    root = executable.basename + ".runfiles"
    relocated = {}
    targets = {}

    (runtime_target, libraries) = depsjson["targets"].items()[0]
    for (library, target) in libraries.items():
        target = dict(target)

        for section in _ASSET_SECTIONS:
            if section not in target:
                continue

            assets = {}
            for (key, properties) in target[section].items():
                found = _locate(entries, key, runtime_identifier)
                if found and found[0] not in beside:
                    (path, file) = found
                    relocated[path] = file
                    properties = dict(properties, localPath = "{}/{}".format(root, to_rlocation_path(ctx, file)))
                assets[key] = properties

            target[section] = assets

        targets[library] = target

    return struct(
        depsjson = dict(depsjson, targets = {runtime_target: targets}),
        relocated = relocated,
    )
