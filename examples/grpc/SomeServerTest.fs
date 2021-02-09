module Tests


open System
open Grpc.Core
open Grpc.HealthCheck
open Grpc.Health.V1
open Xunit
open Helloworld
open System.Threading.Tasks

type GreeterImpl() =
    inherit Greeter.GreeterBase()
    override this.SayHello (request: HelloRequest, context: ServerCallContext): Task<HelloReply> =
            Task.FromResult(HelloReply(Message = "Hello " + request.Name))

[<Fact>]
let ``Server Binds To a Port`` () =
    async {
        let health = HealthServiceImpl()
        let host = "127.0.0.1"
        let port = 6000

        let server = Server()
        server.Services.Add(Health.BindService(health)) 
        server.Services.Add(Greeter.BindService(new GreeterImpl()))
        server.Ports.Add(ServerPort(host, port, ServerCredentials.Insecure)) |> ignore
        server.Start()

        Seq.iter(fun (p: ServerPort) -> Assert.True(p.Port > 0)) server.Ports

        let channel = Channel("127.0.0.1:6000", ChannelCredentials.Insecure)
        let client = new Greeter.GreeterClient(channel)
        let user = "you"

        let reply = client.SayHello(HelloRequest(Name = user))
        Assert.Equal("Hello you", reply.Message)

        do! Async.AwaitTask(channel.ShutdownAsync()) |> Async.Ignore
    }
