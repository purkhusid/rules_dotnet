load("@io_bazel_rules_dotnet//dotnet/private:providers.bzl", "DotnetLibraryInfo", "DotnetResourceListInfo")

# We support only these rule kinds.
_dotnet_rules = [
    "csharp_library",
    "csharp_binary",
    "fsharp_library",
    "fsharp_binary",
]

XProjInfo = provider(
    doc = "XProjInfo holds project info for targets",
    fields = {
        "deps": "List[XProjInfo]: direct dependencies",
    },
)

def _generate_xproj_aspect_impl(target, ctx):
    dep_infos = [dep[XProjInfo] for dep in ctx.rule.attr.deps if XProjInfo in dep]
    # print(target.label)
    # print(target)   
    if hasattr(ctx.rule.attr, "srcs"):
        for f in ctx.rule.files.srcs:
            print(f.path)

    return [XProjInfo(
        deps = dep_infos,
    )]

generate_xproj_aspect = aspect(
    attr_aspects = ["deps"],
    implementation = _generate_xproj_aspect_impl,
    # toolchains = [str(Label("//rust:toolchain"))],
    incompatible_use_toolchain_transition = True,
    # doc = "Annotates rust rules with RustAnalyzerInfo later used to build a rust-project.json",
)

_exec_root_tmpl = "__EXEC_ROOT__/"

def _generate_xproj_impl(ctx):
    for target in ctx.attr.targets:
        if XProjInfo not in target:
            print("yoinks")
            continue

        
    ctx.actions.write(output = ctx.outputs.filename, content = struct(
        sysroot_src = []
    ).to_json())

generate_xproj = rule(
    attrs = {
        "targets": attr.label_list(
            aspects = [generate_xproj_aspect],
            doc = "List of all targets to be generated",
        ),
    },
    outputs = {
        "filename": "projects-map.json",
    },
    implementation = _generate_xproj_impl,
    # toolchains = [str(Label("//rust:toolchain"))],
    incompatible_use_toolchain_transition = True,
    # doc = "Produces a rust-project.json for the given targets. Configure rust-analyzer to load the generated file via the linked projects mechanism.",
)
