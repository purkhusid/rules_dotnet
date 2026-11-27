"""Asserts what a publish leaves in its runfiles tree, and how its deps.json finds it there.

That the host does find it there is asserted by running the publishes, in
BUILD.bazel; how they split into container layers in
//dotnet/private/tests/publish/container_layers.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "publish_binary")

_APP = "//dotnet/private/tests/publish/app_to_publish"

# Where the deps.json points the host, relative to the application's directory.
_RUNFILES = "app_to_publish.runfiles/"

def _publish_test(name, impl, binary = _APP, target_framework = "net10.0", expect_failure = False, **kwargs):
    publish_binary(
        name = name + "_publish",
        binary = binary,
        dependencies_in_runfiles = True,
        # Analysis is all the test needs.
        tags = ["manual"],
        target_framework = target_framework,
        **kwargs
    )

    analysis_test(name = name, impl = impl, target = name + "_publish", expect_failure = expect_failure)

def _copied(target):
    """What the publish copies into its directory: the copy's inputs, less its script."""
    actions = [action for action in target[TestingAspectInfo].actions if action.mnemonic == "DotnetPublishCopy"]
    script_prefix = "{}/{}.".format(target.label.package, target.label.name)

    return [file for action in actions for file in action.inputs.to_list() if not file.short_path.startswith(script_prefix)]

def _depsjson(target):
    """The deps.json the publish writes, decoded."""
    for action in target[TestingAspectInfo].actions:
        if action.mnemonic == "FileWrite" and action.outputs.to_list()[0].basename == "app_to_publish.deps.json":
            return json.decode(action.content)

    fail("{} writes no deps.json".format(target.label))

def _libraries(target):
    return _depsjson(target)["targets"].values()[0]

def _library(target, prefix):
    """The deps.json target of the library whose name starts with `prefix`."""
    return [library for (name, library) in _libraries(target).items() if name.startswith(prefix)][0]

def _rlocation_path(file):
    """Where `file` is in a runfiles tree."""
    return file.short_path.removeprefix("../") if file.short_path.startswith("../") else "_main/" + file.short_path

def _runfile_basenames(target):
    return [file.basename for file in target[DefaultInfo].default_runfiles.files.to_list()]

def _framework_dependent_test(name):
    _publish_test(name, _framework_dependent_test_impl, self_contained = False)

def _framework_dependent_test_impl(env, target):
    # Nothing is copied but the assembly the executable starts.
    env.expect.that_collection([file.basename for file in _copied(target)]).contains_exactly(["app_to_publish.dll"])
    env.expect.that_collection(_runfile_basenames(target)).contains_at_least(["LibGit2Sharp.dll", "data-file"])

    # Each dependency's assets are listed as runtime-specific, which is what
    # every host probes for below the application's directory.
    libgit2sharp = _library(target, "LibGit2Sharp/")
    env.expect.that_dict(libgit2sharp["runtime"]).keys().contains_exactly([])
    env.expect.that_collection(libgit2sharp["runtimeTargets"].keys()).contains_exactly_predicates([
        matching.str_matches(_RUNFILES + "*/LibGit2Sharp.dll"),
    ])
    env.expect.that_str(libgit2sharp["runtimeTargets"].values()[0]["assetType"]).equals("runtime")

    # A package's native libraries, and one built here.
    targets = {path: asset for library in _libraries(target).values() for (path, asset) in library.get("runtimeTargets", {}).items()}
    native = [path for (path, asset) in targets.items() if asset["assetType"] == "native"]
    env.expect.that_collection(native).contains_at_least_predicates([
        matching.str_matches(_RUNFILES + "*libgit2sharp.nativebinaries*/runtimes/*/native/*git2*"),
        matching.str_matches(_RUNFILES + "_main/dotnet/private/tests/publish/app_to_publish/*native*"),
    ])

    # The application's own assembly is beside the executable.
    env.expect.that_collection(_library(target, "app_to_publish/")["runtime"].keys()).contains_exactly(["app_to_publish.dll"])

def _self_contained_test(name):
    _publish_test(name, _self_contained_test_impl, self_contained = True)

def _self_contained_test_impl(env, target):
    # The executable loads the host libraries from beside itself.
    env.expect.that_collection([file.basename for file in _copied(target)]).contains_exactly_predicates([
        matching.equals_wrapper("app_to_publish.dll"),
        matching.str_matches("*hostfxr*"),
        matching.str_matches("*hostpolicy*"),
    ])
    env.expect.that_collection(_runfile_basenames(target)).contains_at_least(["LibGit2Sharp.dll", "System.Private.CoreLib.dll"])

    # The runtime and the dependencies are listed by name, as in any
    # self-contained deps.json, with where each is in the runfiles tree.
    runtime_pack = _library(target, "runtimepack.Microsoft.NETCore.App.Runtime.")
    env.expect.that_collection([
        runtime_pack["runtime"]["System.Private.CoreLib.dll"]["localPath"],
        _library(target, "LibGit2Sharp/")["runtime"]["LibGit2Sharp.dll"]["localPath"],
    ]).contains_exactly_predicates([
        matching.str_matches(_RUNFILES + "*microsoft.netcore.app.runtime.*/System.Private.CoreLib.dll"),
        matching.str_matches(_RUNFILES + "*/LibGit2Sharp.dll"),
    ])

    host = [properties for (name, properties) in runtime_pack["native"].items() if "hostfxr" in name or "hostpolicy" in name]
    env.expect.that_collection(host).contains_exactly([{}, {}])
    env.expect.that_dict(_library(target, "app_to_publish/")["runtime"]["app_to_publish.dll"]).keys().not_contains("localPath")

def _ready_to_run_test(name):
    _publish_test(name, _ready_to_run_test_impl, ready_to_run = True, self_contained = True)

def _ready_to_run_test_impl(env, target):
    # The images take the place of the assemblies, in the runfiles tree as in
    # the publish directory.
    env.expect.that_collection([file.short_path for file in _copied(target) if file.basename == "app_to_publish.dll"]).contains_exactly_predicates([
        matching.str_matches("*/r2r/*/app_to_publish.dll"),
    ])

    local_path = _library(target, "LibGit2Sharp/")["runtime"]["LibGit2Sharp.dll"]["localPath"]
    image = [file for file in target[DefaultInfo].default_runfiles.files.to_list() if file.basename == "LibGit2Sharp.dll"]
    env.expect.that_collection([file.short_path for file in image]).contains_exactly_predicates([matching.str_matches("*/r2r/LibGit2Sharp.dll")])
    env.expect.that_str(local_path).equals(_RUNFILES + _rlocation_path(image[0]))

def _expect_failure(*fragments):
    def _impl(env, target):
        for fragment in fragments:
            env.expect.that_target(target).failures().contains_predicate(matching.contains(fragment))

    return _impl

def _not_with_single_file_test(name):
    _publish_test(
        name,
        _expect_failure("dependencies_in_runfiles cannot be combined with single_file"),
        expect_failure = True,
        self_contained = True,
        single_file = True,
    )

def _not_with_native_aot_test(name):
    _publish_test(
        name,
        _expect_failure("dependencies_in_runfiles cannot be combined with native_aot"),
        expect_failure = True,
        native_aot = True,
        self_contained = True,
    )

def _not_with_ready_to_run_composite_test(name):
    _publish_test(
        name,
        _expect_failure("dependencies_in_runfiles cannot be combined with ready_to_run_composite"),
        expect_failure = True,
        ready_to_run = True,
        ready_to_run_composite = True,
        self_contained = True,
    )

def _self_contained_needs_net10_test(name):
    _publish_test(
        name,
        _expect_failure("needs the host of .NET 10 or later", ":net9_app is built for net9.0"),
        binary = ":net9_app",
        expect_failure = True,
        self_contained = True,
        target_framework = "net9.0",
    )

def dependencies_in_runfiles_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _framework_dependent_test,
            _self_contained_test,
            _ready_to_run_test,
            _not_with_single_file_test,
            _not_with_native_aot_test,
            _not_with_ready_to_run_composite_test,
            _self_contained_needs_net10_test,
        ],
    )
