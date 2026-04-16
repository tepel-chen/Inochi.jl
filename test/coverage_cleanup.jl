InochiCore.eval(quote
    const COVERAGE_READ_CHUNK_BYTES = Ref{Any}(nothing)
    const COVERAGE_READ_CHUNK_COUNT = Ref(0)
    const COVERAGE_ACCEPT_MODE = Ref(:throw)
    const COVERAGE_ACCEPT_SOCKET = Ref{Any}(nothing)
    function accept(::Sockets.TCPServer)
        if COVERAGE_ACCEPT_MODE[] === :socket
            COVERAGE_ACCEPT_MODE[] = :throw
            return COVERAGE_ACCEPT_SOCKET[]
        end
        throw(ErrorException("forced accept failure"))
    end
    function _read_chunk(::Sockets.TCPSocket)
        COVERAGE_READ_CHUNK_COUNT[] += 1
        COVERAGE_READ_CHUNK_COUNT[] == 1 ? COVERAGE_READ_CHUNK_BYTES[] : UInt8[]
    end
end)

@testset "Coverage Cleanup" begin
    with_tcp_pair() do sock, client, server
        InochiCore.COVERAGE_READ_CHUNK_COUNT[] = 0
        InochiCore.COVERAGE_READ_CHUNK_BYTES[] = Vector{UInt8}(codeunits("NOT-H2"))
        @test isnothing(Base.invokelatest(InochiCore._handle_connection, sock, req -> Response(200, Headers()); allow_http1 = false, allow_http2 = true))
    end

    listener = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    @test isnothing(Base.invokelatest(InochiCore.serve, req -> Response(200, Headers()), listener; allow_http1 = true, allow_http2 = false))
    close(listener)

    with_tcp_pair() do sock, client, server
        InochiCore.COVERAGE_ACCEPT_MODE[] = :socket
        InochiCore.COVERAGE_ACCEPT_SOCKET[] = sock
        task = @async InochiCore.serve(req -> Response(200, Headers(["X-Test" => "1"]), "ok"), server; allow_http1 = true, allow_http2 = false)
        try
            write(client, Vector{UInt8}(codeunits("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")))
            flush(client)
        catch
        end
        sleep(0.05)
        close(client)
        @test fetch(task) === nothing
    end

    with_tcp_pair() do sock, client, server
        request_bytes = _make_h2_client_request_bytes([
            ":method" => "GET",
            ":path" => "/coverage",
            ":scheme" => "http",
            ":authority" => "127.0.0.1:8080",
        ])
        magic = collect(codeunits(NghttpWrapper.NGHTTP2_CLIENT_MAGIC))
        rest = request_bytes[length(magic) + 1:end]
        InochiCore.COVERAGE_READ_CHUNK_COUNT[] = 0
        InochiCore.COVERAGE_READ_CHUNK_BYTES[] = rest
        task = @async InochiCore._handle_http2_connection(sock, req -> Response(204, Headers()); prefix = magic)
        @test fetch(task) === nothing
    end

    InochiCore.eval(quote
        using Sockets
        function _feed_h2!(session, sock::Sockets.TCPSocket, chunk::AbstractVector{UInt8})
            throw(ErrorException("forced h2 feed failure"))
        end
    end)
    with_tcp_pair() do sock, client, server
        request_bytes = _make_h2_client_request_bytes([
            ":method" => "GET",
            ":path" => "/coverage-error",
            ":scheme" => "http",
            ":authority" => "127.0.0.1:8080",
        ])
        magic = collect(codeunits(NghttpWrapper.NGHTTP2_CLIENT_MAGIC))
        @test_throws ErrorException InochiCore._handle_http2_connection(sock, req -> Response(204, Headers()); prefix = magic)
    end

    Inochi.eval(quote
        import .Core: serve
        const START_STUB = Ref{Any}(nothing)
        serve(handler; host::AbstractString = "127.0.0.1", port::Integer = 8080, max_content_size::Integer = DEFAULT_MAX_CONTENT_SIZE, kw...) = begin
            START_STUB[] = (; handler, host, port, max_content_size, kw)
            return :started
        end
    end)
    @test Inochi.start(App(); host = "127.0.0.1", port = 4321, allow_http1 = false, allow_http2 = true) == :started
    @test Inochi.START_STUB[].host == "127.0.0.1"
    @test Inochi.START_STUB[].port == 4321
    @test Inochi.START_STUB[].max_content_size == Inochi.DEFAULT_MAX_CONTENT_SIZE
    @test collect(Inochi.START_STUB[].kw) == [:max_threads => Threads.nthreads(), :allow_http1 => false, :allow_http2 => true]

    CoverageRequest = Module(:CoverageRequest)
    Core.eval(CoverageRequest, :(using Sockets, LlhttpWrapper, OpenSSL))
    Core.eval(CoverageRequest, :(import Base: readavailable, readbytes!))
    Base.include(CoverageRequest, joinpath(@__DIR__, "..", "src", "Core", "Headers.jl"))
    Base.include(CoverageRequest, joinpath(@__DIR__, "..", "src", "Core", "Request.jl"))
    Core.eval(CoverageRequest, quote
        const COVERAGE_READ_MODE = Ref(:byte)
        const COVERAGE_READ_BYTE = Ref{UInt8}(0x61)
        readavailable(::Sockets.TCPSocket) = UInt8[]
        readbytes!(::Sockets.TCPSocket, buf::Vector{UInt8}, ::Int64; all::Bool = true) = begin
            COVERAGE_READ_MODE[] === :byte || throw(ErrorException("forced read failure"))
            isempty(buf) && return 0
            buf[1] = COVERAGE_READ_BYTE[]
            return 1
        end
    end)
    with_tcp_pair() do sock, client, server
        CoverageRequest.COVERAGE_READ_MODE[] = :byte
        CoverageRequest.COVERAGE_READ_BYTE[] = 0x62
        @test Base.invokelatest(CoverageRequest._read_chunk, sock) == UInt8[0x62]
        CoverageRequest.COVERAGE_READ_MODE[] = :throw
        @test_throws ErrorException Base.invokelatest(CoverageRequest._read_chunk, sock)
    end
end
