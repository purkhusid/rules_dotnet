open Paket
open Argu
open System
open System.Collections.Generic

type CliArguments =
    | [<Mandatory>] Dependencies_File of path: string
    | [<Mandatory>] Lock_File of path: string
    | [<Mandatory>] Output_Folder of path: string

    interface IArgParserTemplate with
        member s.Usage =
            match s with
            | Dependencies_File _ -> "Path to paket.dependencies file"
            | Lock_File _ -> "Path to paket.lock file"
            | Output_Folder _ -> "Folder where the output will be generated in"

type Package =
    { name: string
      group: string
      version: string
      deps: Package list
      direct: bool }

let rec getPackageDeps
    (depenencies: Dependencies)
    (packageTuple: (string * string * string))
    (cache: Dictionary<string, Package>)
    : Package list =
    let (packageGroup, packageName, packageVersion) = packageTuple

    depenencies.GetDirectDependenciesForPackage((Domain.GroupName packageGroup), packageName)
    |> List.map
        (fun (group, name, version) ->
            let found, value =
                cache.TryGetValue(sprintf "%s-%s" group name)

            match found with
            | true -> value
            | false ->
                let package =
                    { name = name
                      group = group
                      version = version
                      deps = (getPackageDeps depenencies (group, name, version) cache)
                      direct = false }

                cache.Add((sprintf "%s-%s" group name), package)
                package)

let isDirectDependency depGroup depName directDeps =
    directDeps
    |> List.exists (fun (group, name, version) -> group = depGroup && name = depName)

let getDependencies dependenciesFile (cache: Dictionary<string, Package>) =
    let maybeDeps = Dependencies.TryLocate(dependenciesFile)

    match maybeDeps with
    | Some (deps) ->
        // TODO: Make it fail if lockfile is not up to date
        deps.Install false
        let directDeps = deps.GetDirectDependencies()

        deps.GetInstalledPackages()
        |> List.map
            (fun (group, name, version) ->
                let found, value =
                    cache.TryGetValue(sprintf "%s-%s" group name)

                match found with
                | true -> value
                | false ->
                    let fle =
                        deps.GetInstalledPackageModel(Some(group), name)
                    fle.GetCompileReferenceFiles TargetProfile.PortableProfile

                    printfn "%O" fle
                    printfn "%s" "fleflefle"
                    printfn "%s" "fleflefle"
                    printfn "%s" "fleflefle"
                    printfn "%s" "fleflefle"
                    printfn "%s" "fleflefle"
                    printfn "%s" "fleflefle"

                    let package =
                        { name = name
                          group = group
                          version = version
                          deps = getPackageDeps deps (group, name, version) cache
                          direct = isDirectDependency group name directDeps }

                    cache.Add((sprintf "%s-%s" group name), package)
                    |> ignore

                    package)
    | None -> failwith "Failed to locate paket.dependencies file"


[<EntryPoint>]
let main argv =
    let errorHandler =
        ProcessExiter(
            colorizer =
                function
                | ErrorCode.HelpText -> None
                | _ -> Some ConsoleColor.Red
        )

    let parser =
        ArgumentParser.Create<CliArguments>(programName = "paket2bazel", errorHandler = errorHandler)

    let results = parser.ParseCommandLine argv
    let dependenciesFile = results.GetResult Dependencies_File
    let lockFile = results.GetResult Lock_File
    let outputFolder = results.GetResult Output_Folder

    let cache = Dictionary<string, Package>()
    let dependencies = getDependencies dependenciesFile cache

    0 // return an integer exit
