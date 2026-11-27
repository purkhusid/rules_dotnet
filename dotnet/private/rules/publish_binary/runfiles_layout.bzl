"""Points a publish's deps.json at its runfiles tree instead of the publish directory.

A publish lays its files out in a directory, and its deps.json tells the .NET
host where each one is. With `dependencies_in_runfiles`, the files the deps.json
lists stay where Bazel puts them, in the runfiles tree beside the executable,
and the deps.json says so. Only what has to be in the application's directory is
copied there.

The host only follows a path below the application's directory for some assets:

* Those of `runtimeTargets`, which a framework-dependent deps.json can list.
  Every host probes them at the path they are listed under. Assets listed there
  for any runtime identifier are only RID-specific in name.
* Those with a `localPath`, which the host of .NET 10 and later reads. A
  self-contained deps.json cannot list `runtimeTargets`, so a self-contained
  publish needs a runtime pack of .NET 10 or later.

The host anchors the paths at the application's directory, which it finds by
resolving the executable's symlinks. The runfiles tree has to be beside it
there, as Bazel lays it out and as packaging rules carry it.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//dotnet/private:common.bzl", "to_rlocation_path")

# The first version whose host reads `localPath`.
LOCAL_PATH_MIN_MAJOR_VERSION = 10

_ASSET_KINDS = ["runtime", "native", "resources"]

# Kept when an asset moves to `runtimeTargets`: what the host compares an
# application's assembly with a framework's by.
_VERSION_PROPERTIES = ["assemblyVersion", "fileVersion"]

# The host libraries a self-contained executable loads from beside itself.
_HOST_LIBRARIES = ["hostfxr", "hostpolicy"]

def runfiles_root(executable):
    """The runfiles tree of `executable`, relative to the directory it is in."""
    return executable.basename + ".runfiles"

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

def supports_local_path(runtime_pack_info):
    """Whether the host a self-contained publish ships reads `localPath`.

    Args:
        runtime_pack_info: The publish's DotnetRuntimePackInfo.

    Returns:
        True if it does.
    """
    version = runtime_pack_info.assembly_runtime_infos[0].version
    return int(version.split(".")[0]) >= LOCAL_PATH_MIN_MAJOR_VERSION

def _locate(entries, key, runtime_identifier):
    """The publish path and File a deps.json asset key stands for, or None.

    A native library built in this workspace is listed by its name, but laid
    out under `runtimes/<rid>/native/` in a framework-dependent publish.
    """
    for path in [key, "runtimes/{}/native/{}".format(runtime_identifier, key)]:
        if path in entries:
            return (path, entries[path])

    return None

def _relocated(ctx, root, found, beside, relocated):
    """Where an asset is in the runfiles tree, relative to the application's directory.

    None for an asset that stays in the application's directory. Records the
    asset in `relocated` otherwise.
    """
    if found == None or found[0] in beside:
        return None

    (path, file) = found
    relocated[path] = file
    return "{}/{}".format(root, to_rlocation_path(ctx, file))

def _with_local_paths(ctx, target, entries, root, runtime_identifier, beside, relocated):
    """A target whose assets each carry the `localPath` of their runfile."""
    target = dict(target)

    for kind in _ASSET_KINDS:
        if kind not in target:
            continue

        assets = {}
        for (key, properties) in target[kind].items():
            local_path = _relocated(ctx, root, _locate(entries, key, runtime_identifier), beside, relocated)
            assets[key] = dict(properties, localPath = local_path) if local_path else properties

        target[kind] = assets

    return target

def _as_runtime_targets(ctx, target, entries, root, runtime_identifier, rid, beside, relocated):
    """A target whose assets are each listed in `runtimeTargets` under the path of their runfile."""
    target = dict(target)
    moved = {}

    for kind in _ASSET_KINDS:
        if kind not in target:
            continue

        kept = {}
        for (key, properties) in target[kind].items():
            path = _relocated(ctx, root, _locate(entries, key, runtime_identifier), beside, relocated)
            if path == None:
                kept[key] = properties
                continue

            moved[path] = dict(
                {"rid": rid, "assetType": kind},
                **{name: value for (name, value) in properties.items() if name in _VERSION_PROPERTIES}
            )

        target[kind] = kept

    # A package's own runtime-specific assets keep their runtime identifier.
    for (key, properties) in target.get("runtimeTargets", {}).items():
        path = _relocated(ctx, root, _locate(entries, key, runtime_identifier), beside, relocated)
        moved[path or key] = properties

    if moved:
        target["runtimeTargets"] = moved

    return target

def relocate_to_runfiles(ctx, depsjson, entries, executable, runtime_identifier, rid, is_self_contained, beside):
    """Rewrites a publish's deps.json to list each asset where it is in the runfiles tree.

    Args:
        ctx: The rule context.
        depsjson: The deps.json, from `generate_depsjson`, describing `entries`.
        entries: The File each path of the publish directory would hold.
        executable: The publish's executable, beside which the runfiles tree is.
        runtime_identifier: The runtime identifier the publish lays native libraries out for.
        rid: The portable runtime identifier to list framework-dependent assets for.
        is_self_contained: Whether the publish ships the runtime.
        beside: The publish paths that stay in the application's directory even
            though the deps.json lists them.

    Returns:
        A struct of the rewritten `depsjson`, and `relocated`: the File of each
        publish path left in the runfiles tree.
    """
    root = runfiles_root(executable)
    relocated = {}
    targets = {}

    (runtime_target, libraries) = depsjson["targets"].items()[0]
    for (library, target) in libraries.items():
        if is_self_contained:
            targets[library] = _with_local_paths(ctx, target, entries, root, runtime_identifier, beside, relocated)
        else:
            targets[library] = _as_runtime_targets(ctx, target, entries, root, runtime_identifier, rid, beside, relocated)

    return struct(
        depsjson = dict(depsjson, targets = {runtime_target: targets}),
        relocated = relocated,
    )
