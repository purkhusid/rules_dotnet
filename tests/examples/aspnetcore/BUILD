load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "aspnetcore.exe",
    srcs = glob([
        "*.cs",
        "Controllers/*.cs",
    ]),
    target_compatible_with = select({
        "@io_bazel_rules_dotnet//dotnet/toolchain:3.0.100": [],
        "@io_bazel_rules_dotnet//dotnet/toolchain:3.1.100": [],
        "@io_bazel_rules_dotnet//dotnet/toolchain:3.1.407": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        "@core_sdk_stdlib//:Microsoft.AspNetCore.App",
        "@core_sdk_stdlib//:libraryset",
    ],
)
