using Dates
using OpenSSL

InochiCore.eval(quote
    const SERVER_LISTEN_STUB = Ref{Any}(nothing)
    listen(::Sockets.IPAddr, ::Integer; backlog::Integer = 128) = SERVER_LISTEN_STUB[]
end)

function build_test_tls_context()
    cert = X509Certificate()
    key = EvpPKey(rsa_generate_key())
    cert.public_key = key

    name = X509Name()
    add_entry(name, "C", "US")
    add_entry(name, "ST", "Tokyo")
    add_entry(name, "L", "Tokyo")
    add_entry(name, "O", "Inochi")
    add_entry(name, "CN", "127.0.0.1")

    cert.subject_name = name
    cert.issuer_name = name
    Dates.adjust(cert.time_not_before, Second(0))
    Dates.adjust(cert.time_not_after, Year(1))
    sign_certificate(cert, key)

    ssl_ctx = OpenSSL.SSLContext(OpenSSL.TLSServerMethod())
    OpenSSL.ssl_use_certificate(ssl_ctx, cert)
    OpenSSL.ssl_use_private_key(ssl_ctx, key)
    return ssl_ctx
end

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

@testset "TLS" begin
    sslconfig = build_test_tls_context()
    listener = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    _, port = Sockets.getsockname(listener)
    seen_version = Ref(0)
    task = @async InochiCore.serve(req -> begin
        seen_version[] = req.version
        Response(200, Headers(["X-Test" => "1"]), "ok")
    end, listener; allow_http1 = true, allow_http2 = false, sslconfig = sslconfig)
    sleep(0.1)
    response = HTTP.get("https://127.0.0.1:$port/"; require_ssl_verification = false)
    @test response.status == 200
    @test String(response.body) == "ok"
    @test seen_version[] == 1
    close(listener)
    @test fetch(task) === nothing
end
