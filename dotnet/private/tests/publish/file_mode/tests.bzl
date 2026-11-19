"""Asserts how a publish fills its directory: with copies or with symlinks.

That a publish of symlinks runs, once packed into a tar or an image layer, is
asserted by the publish tests that run one: each runs a `_symlink` variant too.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "publish_binary")

_APP = "//dotnet/private/tests/publish/app_to_publish"

_FLAG = str(Label("//dotnet/settings:publish_file_mode"))

def _publish_test(name, impl, config_settings = {}, **kwargs):
    publish_binary(
        name = name + "_publish",
        binary = _APP,
        # Analysis is all the test needs.
        tags = ["manual"],
        target_framework = "net10.0",
        **kwargs
    )

    analysis_test(name = name, impl = impl, target = name + "_publish", config_settings = config_settings)

def _actions(target, mnemonic):
    return [action for action in target[TestingAspectInfo].actions if action.mnemonic == mnemonic]

def _placed(target, mnemonic):
    """What the target's `mnemonic` actions read and write, their scripts aside."""
    script_prefix = "{}/{}.".format(target.label.package, target.label.name)
    inputs = []
    outputs = []

    for action in _actions(target, mnemonic):
        inputs += [file for file in action.inputs.to_list() if not file.short_path.startswith(script_prefix)]
        outputs += action.outputs.to_list()

    return struct(inputs = inputs, outputs = outputs)

def _basenames(files):
    return [file.basename for file in files]

def _expect_publish_filled_by(env, target, actions):
    """Every file of the publish directory but the publish's own comes from `actions`."""
    placed = {file.path: None for action in actions for file in action.outputs}
    executable = target[DefaultInfo].files_to_run.executable.basename

    env.expect.that_collection([
        file.basename
        for file in target[DefaultInfo].files.to_list()
        if file.path not in placed
    ]).contains_exactly([executable, "app_to_publish.deps.json", "app_to_publish.runtimeconfig.json"])

def _expect_copied(env, target):
    env.expect.that_collection(_actions(target, "Symlink")).has_size(0)
    _expect_publish_filled_by(env, target, [_placed(target, "DotnetPublishCopy")])

def _expect_symlinked(env, target):
    copied = _placed(target, "DotnetPublishCopy")
    linked = _placed(target, "Symlink")

    # The application's own assembly is copied: the apphost resolves its real
    # path to find the application's directory.
    env.expect.that_collection(_basenames(copied.outputs)).contains_exactly(["app_to_publish.dll"])
    env.expect.that_collection(copied.inputs).has_size(1)

    # Everything else is a symlink to the file it publishes, one each.
    env.expect.that_collection(linked.inputs).has_size(len(linked.outputs))
    env.expect.that_collection(_basenames(linked.inputs)).contains("LibGit2Sharp.dll")
    _expect_publish_filled_by(env, target, [copied, linked])

    # The layers are copies still, which packaging rules read as plain
    # directories, where a symlink would point back into Bazel's output tree.
    layers = [file for action in _actions(target, "DotnetPublishLayer") for file in action.outputs.to_list()]
    env.expect.that_collection(layers).has_size(4)
    env.expect.that_bool(all([layer.is_directory for layer in layers])).equals(True)

def _default_test(name):
    _publish_test(name, _default_test_impl, self_contained = True)

def _default_test_impl(env, target):
    _expect_copied(env, target)

def _symlink_test(name):
    _publish_test(name, _symlink_test_impl, file_mode = "symlink", self_contained = True)

def _symlink_test_impl(env, target):
    _expect_symlinked(env, target)

    # The runtime pack of a self-contained publish is linked like the rest.
    env.expect.that_collection(_basenames(_placed(target, "Symlink").inputs)).contains("System.Private.CoreLib.dll")

def _flag_test(name):
    _publish_test(name, _symlink_test_impl, config_settings = {_FLAG: "symlink"}, self_contained = True)

def _attribute_over_flag_test(name):
    _publish_test(name, _default_test_impl, config_settings = {_FLAG: "symlink"}, file_mode = "copy", self_contained = True)

def _framework_dependent_test(name):
    _publish_test(name, _framework_dependent_test_impl, file_mode = "symlink", self_contained = False)

def _framework_dependent_test_impl(env, target):
    _expect_symlinked(env, target)

def _ready_to_run_test(name):
    _publish_test(name, _ready_to_run_test_impl, file_mode = "symlink", ready_to_run = True, self_contained = True)

def _ready_to_run_test_impl(env, target):
    _expect_symlinked(env, target)

    # The assembly the apphost starts is the application's ReadyToRun image,
    # which is copied in its place.
    env.expect.that_collection([
        file.short_path
        for file in _placed(target, "DotnetPublishCopy").inputs
        if "/r2r/" in file.short_path
    ]).has_size(1)

def _single_file_test(name):
    _publish_test(name, _single_file_test_impl, file_mode = "symlink", self_contained = True, single_file = True)

def _single_file_test_impl(env, target):
    # What stays beside the executable is linked, and the executable itself,
    # which the bundler writes, is not.
    linked = _placed(target, "Symlink")
    env.expect.that_collection(_actions(target, "DotnetCopySidecars")).has_size(0)
    env.expect.that_collection([file.owner for file in linked.inputs]).contains(Label(_APP + ":native"))
    env.expect.that_collection(linked.outputs).not_contains(target[DefaultInfo].files_to_run.executable)

def file_mode_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _default_test,
            _symlink_test,
            _flag_test,
            _attribute_over_flag_test,
            _framework_dependent_test,
            _ready_to_run_test,
            _single_file_test,
        ],
    )
