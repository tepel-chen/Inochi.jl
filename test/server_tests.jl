InochiCore.eval(quote
    const SERVER_LISTEN_STUB = Ref{Any}(nothing)
    listen(::Sockets.IPAddr, ::Integer; backlog::Integer = 128) = SERVER_LISTEN_STUB[]
end)

@testset "Server" begin
    @test InochiCore._normalize_host("127.0.0.1") isa Sockets.IPAddr
    @test InochiCore._normalize_host("localhost") isa Sockets.IPAddr

    listener1 = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    InochiCore.SERVER_LISTEN_STUB[] = listener1
    calls1 = Ref(0)
    task1 = @async InochiCore.serve(req -> begin
        calls1[] += 1
        Response(200, Headers(["X-Test" => "1"]), "ok")
    end; host = "127.0.0.1", port = 0, allow_http1 = false, allow_http2 = true)
    sleep(0.05)
    close(listener1)
    @test fetch(task1) === nothing
    @test calls1[] == 0

    listener2 = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    calls2 = Ref(0)
    task2 = @async InochiCore.serve(req -> begin
        calls2[] += 1
        Response(200, Headers(["X-Test" => "1"]), "ok")
    end, listener2; allow_http1 = true, allow_http2 = false)
    close(listener2)
    @test fetch(task2) === nothing
    @test calls2[] == 0

    listener3 = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    calls3 = Ref(0)
    task3 = @async InochiCore.serve(req -> begin
        calls3[] += 1
        Response(200, Headers(["X-Test" => "1"]), "ok")
    end, listener3; allow_http1 = true, allow_http2 = false)
    close(listener3)
    @test fetch(task3) === nothing
    @test calls3[] == 0
end
