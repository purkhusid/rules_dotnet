load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "get_highest_compatible_target_framework")

def _tfm_impl(settings, attr):
    _ignore = settings, attr

    incoming_tfm = settings["//transition_test:tfm_flag"]
    transitioned_tfm = get_highest_compatible_target_framework(incoming_tfm, attr.target_frameworks)

    print("Incoming TFM for {0} is: {1}".format(attr.name, incoming_tfm))
    print("Supported TFMs for {0} are: {1}".format(attr.name, attr.target_frameworks))
    print("Selected TFM  for {0} is: {1}".format(attr.name, transitioned_tfm))

    if transitioned_tfm == None:
        fail("Label {0} does not support the target framework: {1}".format(attr.name, incoming_tfm))
    
    # Here would have to find the closest matching TFM and return it or error

    return {"//transition_test:tfm_flag": transitioned_tfm}

tfm_transition = transition(
    implementation = _tfm_impl,
    inputs = ["//transition_test:tfm_flag"],
    outputs = ["//transition_test:tfm_flag"],
)

def _fsharp_library_impl(ctx):
    inputs = []
    for dep in ctx.attr.deps:
        inputs.extend(dep.files.to_list())

    output = ctx.actions.declare_file("%s/%s" % (ctx.attr._target_framework[BuildSettingInfo].value, ctx.label.name))
    command = """
echo Label {1} TFM was: {2} > {0}
for i in {3}; do cat $i >> {0}; done
""".format(
        output.path, 
        ctx.label.name, 
        ctx.attr._target_framework[BuildSettingInfo].value,
        " ".join([d.files.to_list()[0].path for d in ctx.attr.deps])
    )
    ctx.actions.run_shell(
        mnemonic = "FSharpLibrary",
        inputs = inputs,
        outputs = [output],
        command = command,
    )

    return [DefaultInfo(files = depset([output]))]

fsharp_library = rule(
    implementation = _fsharp_library_impl,
    cfg = tfm_transition,
    attrs = {
        "target_frameworks": attr.string_list(),
        "srcs": attr.label_list(allow_files = [".fs"]),
        "deps": attr.label_list(),
        "_target_framework": attr.label(default = "//transition_test:tfm_flag"),

        # This attribute is required to use Starlark transitions. It allows
        # allowlisting usage of this rule. For more information, see
        # https://docs.bazel.build/skylark/config.html#user-defined-transitions.
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)


def _fsharp_binary_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name)

    ctx.actions.run_shell(
        mnemonic = "FSharpBinary",
        inputs = [],
        outputs = [output],
        command = "echo %s > %s" % (ctx.label.name, output.path),
    )

    return [DefaultInfo(files = depset([output]))]

fsharp_binary = rule(
    implementation = _fsharp_binary_impl,
    attrs = {
        "target_framework": attr.label(),
        "srcs": attr.label_list(allow_files = [".fs"]),
        "deps": attr.label_list(),
        # This attribute is required to use Starlark transitions. It allows
        # allowlisting usage of this rule. For more information, see
        # https://docs.bazel.build/skylark/config.html#user-defined-transitions.
        # "_allowlist_function_transition": attr.label(
        #     default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        # ),
    },
)
