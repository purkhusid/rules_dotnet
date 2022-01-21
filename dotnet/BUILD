exports_files(
    ["defs.bzl"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "all_rules",
    srcs = glob([
        "**/*.bzl",
    ]),
    visibility = ["//visibility:public"],
)

toolchain_type(
    name = "toolchain_type_csharp_core",
    visibility = ["//visibility:public"],
)

toolchain_type(
    name = "toolchain_type_fsharp_core",
    visibility = ["//visibility:public"],
)
 
# This is the target rule authors should put in their "toolchains"
# attribute in order to get a runtime for the correct platform.
# See https://docs.bazel.build/versions/main/toolchains.html#writing-rules-that-use-toolchains
toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)
