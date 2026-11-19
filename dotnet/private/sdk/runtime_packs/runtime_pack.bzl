".Net Runtime Pack"

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetRuntimePackInfo", "NuGetInfo")
load("//dotnet/private/rules/common:copy_script.bzl", "run_copy_script")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

_TOOLCHAIN_TYPE = "//dotnet/toolchain:toolchain_type"

def _layer(ctx, runtime_infos):
    """The packs laid out as the runtime layer of a self-contained publish.

    Every publish of the same framework and runtime identifier reaches this
    target in the same configuration, so the layer is built once for all of
    them rather than copied into each.

    The files sit at their basenames, as `publish_layout` places them in a
    publish, with a later pack's file taking the place of an earlier one's.
    """
    files = {
        file.basename: file
        for info in runtime_infos
        for file in info.libs + info.native + info.data
    }

    # A browser's pack never reaches a publish with layers, and it is built
    # for a platform no .NET toolchain runs on.
    toolchain = ctx.toolchains[_TOOLCHAIN_TYPE]

    if not files or toolchain == None:
        return None

    directory = ctx.actions.declare_directory("{}/layer".format(ctx.label.name))
    run_copy_script(
        ctx.actions,
        "{}.layer".format(ctx.label.name),
        [(files[path], path) for path in sorted(files)],
        "DotnetRuntimeLayer",
        "Assembling the runtime layer of %{label}",
        is_windows = toolchain.dotnetinfo.os == "windows",
        hardlink = ctx.attr._publish_file_mode[BuildSettingInfo].value != "copy",
        directory = directory,
    )

    return struct(directory = directory, files = files)

def _runtime_pack_impl(ctx):
    compile_infos = []
    runtime_infos = []
    nuget_infos = []
    for pack in ctx.attr.packs:
        if pack[DotnetAssemblyCompileInfo]:
            compile_infos.append(pack[DotnetAssemblyCompileInfo])
        if pack[DotnetAssemblyRuntimeInfo]:
            runtime_infos.append(pack[DotnetAssemblyRuntimeInfo])
        if pack[NuGetInfo]:
            nuget_infos.append(pack[NuGetInfo])

    return [DotnetRuntimePackInfo(
        runtime_identifier = ctx.attr.runtime_identifier,
        assembly_runtime_infos = runtime_infos,
        nuget_infos = nuget_infos,
        layer = _layer(ctx, runtime_infos),
    )]

runtime_pack = rule(
    _runtime_pack_impl,
    doc = """.Net runtime Pack""",
    attrs = {
        "packs": attr.label_list(
            cfg = tfm_transition,
            doc = "List of .Net runtime Packs that make this pack",
        ),
        "target_framework": attr.string(
            doc = "The target framework of the runtime pack",
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier of the runtime pack",
        ),
        "_publish_file_mode": attr.label(
            default = "//dotnet/settings:publish_file_mode",
            providers = [BuildSettingInfo],
        ),
    },
    toolchains = [config_common.toolchain_type(_TOOLCHAIN_TYPE, mandatory = False)],
)
