open FSharp.Data

type private FooJson =
  JsonProvider<"./foo.json", SampleIsList=false, InferTypesFromValues=true>

[<EntryPoint>]
let main argv =
  let json = "{ \"foo\": [ 1, 2, 3 ] }"

  let p = FooJson.Parse json

  printfn "%A" p.Foo

  0