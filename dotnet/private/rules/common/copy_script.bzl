"""One action that copies files into place, batched so it starts few processes.

Shared by `publish_binary`, which assembles a publish and its container
layers, and the runtime packs, which assemble the runtime layer every
self-contained publish of a pack can share.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")

# How many sources one `cp` invocation takes. A self-contained publish copies
# several hundred files into one directory, and the point of batching is lost if
# the command line grows long enough to risk the execve argument limit.
_COPY_BATCH = 128

# Hard links a batch of files into a directory, copying them instead where the
# filesystem cannot link them: across devices, as with a sandbox on tmpfs, or
# on a filesystem without hard links. `-L` links what an input symlink points
# at, never the symlink a sandbox stages the input as. A batch that fails part
# way is copied whole, so whatever it linked is removed first: `cp` refuses to
# copy a file onto a link to itself.
_HARDLINK_FUNCTIONS = [
    "place() {",
    "  local dir=\"$1\" src",
    "  shift",
    "  ln -fL -- \"$@\" \"$dir\" 2>/dev/null && return 0",
    "  for src in \"$@\"; do rm -f -- \"$dir/${src##*/}\"; done",
    "  cp -f -- \"$@\" \"$dir\"",
    "}",
    "place_as() {",
    "  ln -fL -- \"$1\" \"$2\" 2>/dev/null && return 0",
    "  rm -f -- \"$2\"",
    "  cp -f -- \"$1\" \"$2\"",
    "}",
]

def _render_copy_script(copies, is_windows, directories = [], hardlink = False):
    """The script that puts every published file in its place.

    A self-contained publish copies the whole runtime pack, so one process per
    file - and a second one to create its directory - dominates the action.
    Each directory is created once instead, and the files that keep their name
    are copied in batches.

    Args:
        copies: The (source, destination path) pairs to copy, one pair per destination.
        is_windows: Whether the script is a batch file rather than a shell script.
        directories: Directories to create even when no file lands in them.
        hardlink: Whether to hard link the files where the filesystem allows,
            rather than copy them. Ignored on Windows.

    Returns:
        A list of script lines.
    """
    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]
    hardlink = hardlink and not is_windows

    if hardlink:
        script_body.extend(_HARDLINK_FUNCTIONS)

    # Grouped by destination directory, in first-seen order. A file published
    # under a different name cannot join a batch, but its directory is still
    # created along with the rest.
    same_name = {directory: [] for directory in directories}
    renamed = []

    for (src, dst) in copies:
        same_name.setdefault(paths.dirname(dst), [])
        if src.basename == paths.basename(dst):
            same_name[paths.dirname(dst)].append(src)
        else:
            renamed.append((src, dst))

    for (directory, sources) in same_name.items():
        if is_windows:
            script_body.append("if not exist \"{dir}\" @mkdir \"{dir}\" >NUL".format(dir = directory.replace("/", "\\")))

            # `copy` concatenates when handed several sources, so only the
            # directory creation is shared on Windows.
            for src in sources:
                script_body.append("@copy /Y \"{src}\" \"{dir}\" >NUL".format(
                    src = src.path.replace("/", "\\"),
                    dir = directory.replace("/", "\\"),
                ))
            continue

        script_body.append("mkdir -p {dir}".format(dir = shell.quote(directory)))

        for start in range(0, len(sources), _COPY_BATCH):
            srcs = " ".join([shell.quote(src.path) for src in sources[start:start + _COPY_BATCH]])

            if hardlink:
                script_body.append("place {dir} {srcs}".format(srcs = srcs, dir = shell.quote(directory)))
            else:
                script_body.append("cp -f {srcs} {dir}".format(srcs = srcs, dir = shell.quote(directory)))

    for (src, dst) in renamed:
        if is_windows:
            script_body.append("@copy /Y \"{src}\" \"{dst}\" >NUL".format(
                src = src.path.replace("/", "\\"),
                dst = dst.replace("/", "\\"),
            ))
        else:
            script_body.append("{cmd} {src} {dst}".format(
                cmd = "place_as" if hardlink else "cp -f",
                src = shell.quote(src.path),
                dst = shell.quote(dst),
            ))

    return script_body

def run_copy_script(actions, name, copies, mnemonic, progress_message, is_windows, hardlink = False, directory = None):
    """Runs one action that puts every (source, destination) pair in place.

    Args:
        actions: The rule's `ctx.actions`.
        name: The script's name, without its extension; unique within the target.
        copies: The (source, destination) pairs to copy. A destination is a
            File, or a path inside `directory` when one is given.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.
        is_windows: Whether the machine running the action is Windows. The
            script runs where the action does, not on the platform built for,
            so this comes from the toolchain resolved for the execution
            platform.
        hardlink: Whether to hard link the files where the filesystem allows,
            rather than copy them. See //dotnet/settings:publish_file_mode.
        directory: The directory to copy into, which is then the only output.

    Returns:
        The action's outputs.
    """
    if directory:
        # Created even when nothing lands in it, because a remote worker does
        # not create a declared directory.
        outputs = [directory]
        directories = [directory.path]
        pairs = [(src, "{}/{}".format(directory.path, dst)) for (src, dst) in copies]
    else:
        outputs = [dst for (_, dst) in copies]
        directories = []
        pairs = [(src, dst.path) for (src, dst) in copies]

    script = actions.declare_file("{}.{}".format(name, "bat" if is_windows else "sh"))

    actions.write(
        output = script,
        content = ("\r\n" if is_windows else "\n").join(_render_copy_script(pairs, is_windows, directories, hardlink = hardlink)),
        is_executable = True,
    )
    actions.run(
        executable = script,
        inputs = depset([src for (src, _) in copies]),
        outputs = outputs,
        tools = [script],
        mnemonic = mnemonic,
        progress_message = progress_message,
    )

    return outputs
