# Exploration: disk used by `publish_binary`

## TL;DR

Almost all of the duplicate bytes come from one place: **every `publish_binary`
physically copies its whole closure** (runtime pack, NuGet DLLs, first-party
DLLs) into `<name>/publish/<rid>/`. If the container-layer output groups are
built, **it copies all of it a second time** into `<name>/layers/*`. The
files being copied already sit on disk in `external/` (the repository
cache) or elsewhere in `bazel-out`, so every one of those copies is redundant.

On a small synthetic monorepo (8 apps, 30 publishes), `bazel-out` drops from
**2.7 GB to 0.53 GB** (-80%) with a prototype that links the files instead of
copying them. Without the single-file bundles, which can't be deduplicated, it
drops from **1.9 GB to 97 MB** (-95%). Every published app still runs.

The prototype is on branch `claude/rules-dotnet-disk-usage-9gx36t` and has two
parts:

- A new flag
  `--@rules_dotnet//dotnet/settings:publish_file_mode=copy|hardlink|symlink`.
  The default `copy` keeps today's behaviour.
- One runtime layer shared by every self-contained publish of the same runtime
  pack, plus a `dotnet_runtime_layer` rule that names it. This is on whatever
  the flag says, and needs no links at all. See
  [Shared runtime layer](#shared-runtime-layer).

## Where the duplicates come from

Measured by hashing every regular file in `bazel-out` after a clean build
(symlinks don't count; hard links count once).

| Source | Rule / action | Size per publish | Notes |
|---|---|---|---|
| Publish directory | `DotnetPublishCopy` (`_copy_to_publish`) | ~76 MB runtime pack for a self-contained net9 linux-x64 app, plus every NuGet and first-party DLL | **Main source.** Always built. |
| Container layers | `DotnetPublishLayer` (`_publish_layers`) | Same bytes again; `runtime` layer ~76 MB | Built only when a `*_layer` output group is requested, but then for every publish. |
| Sidecars (single-file / NativeAOT) | `DotnetCopySidecars` | small | Same pattern. |
| Single-file host intermediate | `DotnetSingleFileHost` → `bundle/<rid>/<app>` | ~11.8 MB | A stamped copy of `singlefilehost` that only the bundler reads. |
| Single-file bundle itself | `DotnetSingleFileBundle` | ~87 MB | Can't be deduplicated: each bundle embeds the runtime. |
| Per-RID library builds | compile actions in each `-ST-<hash>` config | size of the library DLLs | `lib_a.dll` is byte-identical across the linux-x64 / linux-arm64 / win-x64 configs, so each library is compiled and stored once per RID. Small next to the above (~0.5 MB in the bench), but it costs CPU too. |
| NativeAOT `.o` / `.exports` | `Ilc` | tens of MB | Not measured (needs the LLVM toolchain). It's an intermediate Bazel keeps around. |

These don't add duplicates: `nuget_pack` writes the `.nupkg` straight from
source files, and ReadyToRun images of NuGet/first-party assemblies are compiled
once per configuration and shared by every publish.

## Measurements

Bench: 8 `csharp_binary` apps sharing two libraries and
`Microsoft.CodeAnalysis.{Common,CSharp}` (~9 MB of NuGet DLLs), net9.0:

- 8 self-contained linux-x64 publishes, with all 4 layer output groups built
- 4 framework-dependent publishes
- 2 apps × {linux-arm64, win-x64} self-contained
- (bench B only) 4 single-file and 4 ReadyToRun self-contained publishes

| Bench | Mode | `bazel-out` (du) | Duplicate bytes | Actions | Build time |
|---|---|---|---|---|---|
| A | copy (today) | **1.9 GB** | 1728 MB (87%) | 307 | 23 s |
| A | hardlink | 255 MB\* | 3.5 MB | 307 | 22 s |
| A | symlink | **97 MB** | 0.6 MB | 3007 | 20 s |
| B | copy (today) | **2.7 GB** | 2177 MB (75%) | 391 | 26 s |
| B | hardlink | 684 MB\* | – | 391 | – |
| B | symlink | **527 MB** | 1.5 MB | 3947 | 24 s |

\* `du` on `bazel-out` alone counts the hard-linked NuGet/runtime-pack inodes,
which are shared with the repository cache. Counting `bazel-out` and the
repository cache together, hardlink and symlink use the same real disk:
**7.2 GB vs 9.4 GB with copy** for bench B. In bench B, 4 × 87 MB of what's
left in symlink mode is the single-file bundles.

What I checked for each mode: a self-contained app runs, a framework-dependent
app runs, a self-contained app runs after `cp -r` out of `bazel-bin`, single-file
and ReadyToRun apps run, layers hold only regular files, and a no-op rebuild runs
nothing.

Repo tests (`//dotnet/private/tests/publish/...` and `//dotnet/private/tests/ready_to_run/...`,
56 tests) in all three modes: 39 pass. 17 fail in every mode, including on an
unmodified `copy` build, because this runner has no `file` command, which the
cross-compilation and cross-publish tests use to check a binary's architecture.
At first, symlink mode also failed 7 `container_layers` analysis tests. They found
the publish copy by the `DotnetPublishCopy` / `DotnetCopySidecars` mnemonics, and
Bazel's symlink actions are always `Symlink`. The prototype adds `Symlink` to that
list, and all 15 `container_layers` tests now pass in copy and symlink mode. The
tests that stack the layers into a filesystem and run the app pass in every mode.

## Findings that shape the design

1. **The apphost resolves the app directory from the *real path* of the main
   DLL.** In my first symlink attempt, the self-contained app failed with
   `Failed to resolve libhostfxr.so`. The host trace showed `app-local:
   .../bin/disk_bench/app0/net9.0/`: it had followed `app0.dll` back to where it
   was compiled. So the main DLL has to be a real file. Every other file
   (hostfxr, coreclr, CoreLib, NuGet DLLs, native libs) works fine as a symlink.
   The prototype copies (or hard links) just that one file.
2. **Layers have to hold real files.** Packagers like rules_img walk the layer
   directory, and a symlink in there would end up in the image as a symlink to
   a host path. That's why symlink mode hard links the layers.
3. **Hard links share permissions with their source.** Bazel `chmod`s every
   output to `0555`. With a hard link, that also changes the NuGet/runtime-pack
   file in Bazel's **repository contents cache**, which every workspace of that
   user shares. I saw those files turn `r-xr-xr-x`, and their ctime change. The
   next build then re-checked the dependent actions (114 action-cache hits in
   hardlink mode, 2056 in symlink mode). Nothing re-executed, and the build after
   that was clean again. `bazel_lib`'s `copy_to_directory(hardlink = ...)` documents
   the same caveat. That's why its default `auto` only hard links files that are
   already outputs.
4. **Hard links fall back cleanly.** With `--sandbox_base` on a different
   filesystem, `ln` fails with EXDEV and the script copies instead (link count
   1). The build passes and the app runs. Windows isn't covered: the prototype
   keeps copying there.
5. **The publish directory already contains symlinks today.** The
   `<app>.runfiles/` tree (`MANIFEST`, `_repo_mapping`, the executable) is a
   Bazel symlink tree, so `cp -r bazel-bin/.../publish/<rid>` already copies
   absolute links into the output base. Symlink mode makes that true for every
   file, so `cp -rL` (or a packaging rule) is required to ship the directory.

## Options compared

| | copy (today) | hardlink | symlink |
|---|---|---|---|
| Local disk | N × closure | ~0 | ~0 |
| Remote exec / Build without the Bytes | N × closure downloaded | no help (files are downloaded separately) | ~0: symlink actions only record metadata, no download |
| What consumers see | real files | real files | symlinks in `bazel-bin` (any Bazel rule still sees file contents) |
| Side effects | none | `chmod 0555` on cached NuGet/runtime files, one-off re-check on the next build | none for the publish directory (its layers are hard linked) |
| Action count | 1 per publish | 1 per publish | 1 per published file (Bazel-internal, no process) |
| Windows | – | copies | Bazel copies unless `--windows_enable_symlinks` |

## Recommendations

1. **Symlink the publish directory** (`ctx.actions.symlink`, main DLL kept
   real). It's the Bazel-native way to do this: no side effects on sources, and
   it works for local, remote and BwoB builds. This is most of the win. Ship it
   behind the flag first, then consider making it the default with a release
   note (`cp -rL`).
2. **Share the runtime layer rather than link it** (prototyped, see below). Keep
   `hardlink` as an opt-in for the third-party and first-party layers on local
   builds.
3. **Smaller follow-ups:**
   - Stamp and bundle the single-file host in one action. That saves the
     ~11.8 MB `bundle/<rid>/<app>` intermediate per single-file publish.
   - Consider running `Ilc` and `IlcLink` as one action so the NativeAOT
     object file isn't kept around. The trade-off is losing separate caching
     of the two steps.
   - Look into building libraries in a RID-independent configuration. Their IL
     doesn't depend on the RID, but `//dotnet:rid` puts them in a different
     output directory per RID. Path mapping already shares the cache key, but
     not the disk or the local work. This is a bigger change, because
     `select()`s on `rid_compatible_*` have to keep working.

## Shared runtime layer

The `runtime` layer (~76 MB) is ~80% of the layer bytes. It's identical for
every self-contained publish of the same runtime pack, so the prototype builds
it once.

**How it works.** Every binary already reaches its runtime pack through
`runtime_pack_transition`. That transition keeps the framework and RID and
resets the ReadyToRun and publish settings. So all publishes of one framework,
RID and project SDK see the same configured `runtime_pack` target, ReadyToRun
publishes included.

- `runtime_pack` lays the pack out once as a `layer` directory, using the copy
  script now shared from `dotnet/private/rules/common/copy_script.bzl`. It
  returns the directory and its file list on `DotnetRuntimePackInfo.layer`.
- `_publish_layers` compares its own runtime layer, path by path, with the
  pack's file list. If they match, it returns the pack's directory as its
  `runtime_layer` output group and declares no copy action.
- Otherwise it copies its own layer as before. That happens when a dependency
  carries a newer version of one of the runtime's assemblies, which then takes
  that assembly's place, or with composite ReadyToRun, single-file and
  NativeAOT publishes. The comparison catches all of these, with no list of
  special cases to keep in sync.
- `dotnet_runtime_layer(target_framework, runtime_identifier, project_sdk)`
  goes through the same transitions and returns the same directory. That gives
  users one target to pack into one `image_layer` that every image reuses.
  Sharing the directory alone doesn't stop rules_img from packing one tarball
  per `image_layer` target.

**Results** (bench B):

- In `copy` mode, `bazel-out` goes from 2.7 GB to 2.2 GB, and per-publish layer
  copies from 764 MB to 128 MB plus one 76 MB shared runtime layer.
- In `symlink` mode nothing changes (526 MB), because the layers there were
  already hard links.
- `bazel cquery` shows the eight self-contained publishes, four ReadyToRun
  publishes and `dotnet_runtime_layer` all returning the same
  `.../dotnet.runtime_packs/default/net9.0/linux-x64/layer`.

**Tests.** The `container_layers` analysis tests now accept the shared layer,
and say for each kind of publish whether it shares. Two tests are new:

- `shared_runtime_layer_test`: two applications, a ReadyToRun publish and
  `dotnet_runtime_layer` return one directory, and no publish copies a runtime
  layer of its own.
- `overridden_runtime_assembly_test`: a net8.0 app depending on
  `System.Formats.Asn1 10.0.5` keeps its own runtime layer without the pack's
  `System.Formats.Asn1.dll`. The package's copy is in `third_party`.

The shell tests that stack the rules_img tarballs and run the app still pass.
They were cache hits: the tarball packed from the shared directory is
byte-identical to the one packed from the per-publish copy.

**Trade-offs:**

- The `runtime_layer` output group now points into the runtime pack's external
  repository instead of `<name>/layers/runtime`. rules_img doesn't care, but a
  tool that expected the old path would.
- Every `runtime_pack` now resolves the .NET toolchain to know which copy
  script to write. It's optional, so a pack no toolchain runs on, like the
  browser's, simply has no layer.
- Sharing holds only while the configurations match. A user transition that
  splits a binary's configuration splits its runtime layer too.

## Appendix: reproducing

To rerun the bench, put these files in `examples/disk_bench/`. I didn't commit
them as a package, to keep 30 extra publishes out of the examples build.

```csharp
// LibA.cs
namespace DiskBench;

public static class LibA
{
    public static string Describe() =>
        Microsoft.CodeAnalysis.CSharp.SyntaxFactory.ParseExpression("1 + 2").ToString();
}
```

```csharp
// LibB.cs
namespace DiskBench;

public static class LibB
{
    public static string Greet(string who) => $"Hello {who}: {LibA.Describe()}";
}
```

```csharp
// Program.cs.tpl
System.Console.WriteLine(DiskBench.LibB.Greet("APPNAME"));
```

`BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary", "csharp_library", "dotnet_runtime_layer", "publish_binary")

csharp_library(name = "lib_a", srcs = ["LibA.cs"], target_frameworks = ["net9.0"],
    deps = ["@paket.example_deps//microsoft.codeanalysis.common",
            "@paket.example_deps//microsoft.codeanalysis.csharp"])
csharp_library(name = "lib_b", srcs = ["LibB.cs"], target_frameworks = ["net9.0"], deps = [":lib_a"])

APPS = ["app%d" % i for i in range(8)]
[genrule(name = a + "_src", srcs = ["Program.cs.tpl"], outs = [a + "/Program.cs"],
         cmd = "sed s/APPNAME/%s/ $< > $@" % a) for a in APPS]
[csharp_binary(name = a, srcs = [a + "_src"], target_frameworks = ["net9.0"], deps = [":lib_b"]) for a in APPS]
[publish_binary(name = a + "_sc", binary = a, self_contained = True, target_framework = "net9.0") for a in APPS]
[publish_binary(name = a + "_fd", binary = a, target_framework = "net9.0") for a in APPS[:4]]
[filegroup(name = "%s_sc_%s" % (a, l), srcs = [a + "_sc"], output_group = l + "_layer")
 for a in APPS for l in ["runtime", "third_party", "first_party", "app"]]
[publish_binary(name = "%s_sc_%s" % (a, rid), binary = a, runtime_identifier = rid,
                self_contained = True, target_framework = "net9.0")
 for a in APPS[:2] for rid in ["linux-arm64", "win-x64"]]
# Bench B adds:
[publish_binary(name = a + "_single_file", binary = a, self_contained = True, single_file = True,
                target_framework = "net9.0") for a in APPS[:4]]
[publish_binary(name = a + "_r2r", binary = a, ready_to_run = True, self_contained = True,
                target_framework = "net9.0") for a in APPS[:4]]
[filegroup(name = a + "_r2r_runtime", srcs = [a + "_r2r"], output_group = "runtime_layer") for a in APPS[:4]]
dotnet_runtime_layer(name = "net9_runtime", target_framework = "net9.0")
```

```bash
bazel clean && bazel build //disk_bench:all --@rules_dotnet//dotnet/settings:publish_file_mode=symlink
du -sh "$(bazel info output_path)"
```
