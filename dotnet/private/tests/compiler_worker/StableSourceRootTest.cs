using System.Collections.Generic;
using FSharpCompilerWorker;
using NUnit.Framework;

namespace RulesDotnet.Tests;

[TestFixture]
public class StableSourceRootTest
{
    private const string Root = "/proc/self/cwd";

    [Test]
    public void ARelativeSourceFileGoesUnderTheRoot()
    {
        // Act
        var arguments = StableSourceRoot.Apply(new[] { "src/Library.fs", "src/with space/Other.fs" }, Root);

        // Assert
        Assert.That(arguments[0], Is.EqualTo("/proc/self/cwd/src/Library.fs"));
        Assert.That(arguments[1], Is.EqualTo("/proc/self/cwd/src/with space/Other.fs"));
    }

    [Test]
    public void AnAbsoluteSourceFileIsLeftAlone()
    {
        // Act
        var arguments = StableSourceRoot.Apply(new[] { "/workspace/src/Library.fs" }, Root);

        // Assert
        Assert.That(arguments[0], Is.EqualTo("/workspace/src/Library.fs"));
    }

    [TestCase("--out:bazel-out/bin/a.dll", "--out:/proc/self/cwd/bazel-out/bin/a.dll")]
    [TestCase("-o:bazel-out/bin/a.dll", "-o:/proc/self/cwd/bazel-out/bin/a.dll")]
    [TestCase("--pdb:bazel-out/bin/a.pdb", "--pdb:/proc/self/cwd/bazel-out/bin/a.pdb")]
    [TestCase("--refout:bazel-out/bin/ref/a.dll", "--refout:/proc/self/cwd/bazel-out/bin/ref/a.dll")]
    [TestCase("--PDB:bazel-out/bin/a.pdb", "--PDB:/proc/self/cwd/bazel-out/bin/a.pdb")]
    [TestCase("--pdb:/abs/a.pdb", "--pdb:/abs/a.pdb")]
    public void AnOutputPathGoesUnderTheRoot(string argument, string expected)
    {
        // Act
        var arguments = StableSourceRoot.Apply(new[] { argument }, Root);

        // Assert
        Assert.That(arguments[0], Is.EqualTo(expected));
    }

    [Test]
    public void EveryFileToEmbedGoesUnderTheRootWithItsSeparatorKept()
    {
        // Act
        var arguments = StableSourceRoot.Apply(new[] { "--embed:src/A.fs,src/B.fs;/abs/C.fs" }, Root);

        // Assert
        Assert.That(arguments[0], Is.EqualTo("--embed:/proc/self/cwd/src/A.fs,/proc/self/cwd/src/B.fs;/abs/C.fs"));
    }

    [TestCase("--embed+")]
    [TestCase("--debug:portable")]
    [TestCase("-r:bazel-out/bin/b.dll")]
    [TestCase("--doc:bazel-out/bin/a.xml")]
    [TestCase("--resource:src/a.txt,a.txt")]
    [TestCase("--define:TRACE")]
    public void AnyOtherOptionIsLeftAlone(string argument)
    {
        // Act
        var arguments = StableSourceRoot.Apply(new[] { argument }, Root);

        // Assert
        Assert.That(arguments[0], Is.EqualTo(argument));
    }

    [Test]
    public void ThePathmapMapsTheRootBackToTheWorkingDirectory()
    {
        // Act
        var arguments = StableSourceRoot.Apply(new List<string> { "src/Library.fs" }, Root);

        // Assert
        Assert.That(arguments, Is.EqualTo(new[] { "/proc/self/cwd/src/Library.fs", "--pathmap:/proc/self/cwd=." }));
    }

    [Test]
    public void ADiagnosticNamesItsSourceRelativeToTheWorkingDirectory()
    {
        // Act
        var output = StableSourceRoot.Unapply(
            "/proc/self/cwd/src/Library.fs(3,5): warning FS0025: Incomplete pattern matches on this expression.",
            Root);

        // Assert
        Assert.That(output, Is.EqualTo("src/Library.fs(3,5): warning FS0025: Incomplete pattern matches on this expression."));
    }
}
