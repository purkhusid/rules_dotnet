#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace FSharpCompilerWorker
{
    /// <summary>
    /// Hands fsc its source files under <c>/proc/self/cwd</c>, a name for the
    /// working directory that reads the same in every execution root.
    /// </summary>
    /// <remarks>
    /// fsc joins each relative path onto the working directory and records the
    /// result in places its <c>--pathmap</c> does not reach: the source location
    /// a quotation literal carries, the location a <c>MatchFailureException</c>
    /// reports, and the room the debug directory reserves for the PDB path. A
    /// worker slot, a sandbox and a remote executor each have a working directory
    /// of their own, so without this the same compile gives a different assembly
    /// in each. The pathmap still turns every path it does reach into <c>./</c>.
    /// </remarks>
    internal static class StableSourceRoot
    {
        private const string ProcSelfCwd = "/proc/self/cwd";

        /// <summary>
        /// The options whose value is a path fsc records or compares against a
        /// source path: the PDB path is written to the debug directory, the
        /// assembly paths are what a PDB path defaults from, and an embedded
        /// source only matches a source file by its full path.
        /// </summary>
        private static readonly HashSet<string> PathOptions =
            new(StringComparer.OrdinalIgnoreCase) { "out", "o", "pdb", "refout" };

        /// <summary><c>--embed:</c> names files; <c>--embed+</c> and <c>--embed-</c> do not.</summary>
        private const string PathListOption = "embed";

        private static readonly Regex Option = new("^(?<flag>--?(?<name>[A-Za-z]+):)(?<value>.*)$", RegexOptions.Singleline);

        /// <summary>
        /// <c>/proc/self/cwd</c>, or null where the platform has no such name
        /// for the working directory and the compile goes ahead as it always has.
        /// </summary>
        public static string? Find() =>
            OperatingSystem.IsLinux() && Directory.Exists(ProcSelfCwd) ? ProcSelfCwd : null;

        /// <summary>
        /// <paramref name="arguments"/> with every relative source file and path
        /// option under <paramref name="root"/>, and a pathmap that maps
        /// <paramref name="root"/> back to <c>.</c>.
        /// </summary>
        public static List<string> Apply(IEnumerable<string> arguments, string root)
        {
            var rooted = new List<string>();
            foreach (var argument in arguments)
            {
                rooted.Add(ApplyTo(argument, root));
            }

            rooted.Add("--pathmap:" + root + "=.");
            return rooted;
        }

        /// <summary>
        /// The compiler's output with <paramref name="root"/> taken back out of
        /// the paths in its diagnostics, which then read relative to the
        /// execution root, as Bazel's own messages do.
        /// </summary>
        public static string Unapply(string output, string root) =>
            output.Replace(root + "/", "", StringComparison.Ordinal);

        private static string ApplyTo(string argument, string root)
        {
            if (!argument.StartsWith('-'))
            {
                return Under(root, argument);
            }

            var option = Option.Match(argument);
            if (!option.Success)
            {
                return argument;
            }

            var name = option.Groups["name"].Value;
            var value = option.Groups["value"].Value;
            if (PathOptions.Contains(name))
            {
                return option.Groups["flag"].Value + Under(root, value);
            }

            if (name.Equals(PathListOption, StringComparison.OrdinalIgnoreCase))
            {
                return option.Groups["flag"].Value + Regex.Replace(value, "[^,;]+", file => Under(root, file.Value));
            }

            return argument;
        }

        private static string Under(string root, string path) =>
            path.Length == 0 || Path.IsPathRooted(path) ? path : root + "/" + path;
    }
}
