import Sockets
using NghttpWrapper

function parse_raw_request(raw::String; max_content_size::Integer = typemax(Int))
    bytes = Vector{UInt8}(codeunits(raw))
    state_ref = Ref(InochiCore._RequestState(max_content_size))
    parser = InochiCore.LlhttpWrapper.Parser(InochiCore.LlhttpWrapper.HTTP_REQUEST; settings = InochiCore._parser_settings())
    InochiCore.LlhttpWrapper.set_userdata!(parser, Base.pointer_from_objref(state_ref))
    GC.@preserve state_ref parser bytes begin
        code = InochiCore.LlhttpWrapper.execute!(parser, bytes)
        code == InochiCore.LlhttpWrapper.HPE_OK || code == InochiCore.LlhttpWrapper.HPE_PAUSED || code == InochiCore.LlhttpWrapper.HPE_PAUSED_UPGRADE || error("parse failed")
        queued = InochiCore._next_completed_request(state_ref[])
        queued === nothing && error("incomplete HTTP request")
        return queued.request
    end
end

function with_tcp_pair(f::Function)
    server = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    port = Sockets.getsockname(server)[2]
    client = Sockets.connect(Sockets.IPv4(127, 0, 0, 1), port)
    sock = Sockets.accept(server)
    try
        return f(sock, client, server)
    finally
        Sockets.close(client)
        Sockets.close(sock)
        Sockets.close(server)
    end
end

@testset "Core Types" begin
    @testset "Headers" begin
        backing = "FooBar"
        data_headers = InochiCore.Headers(["X-Test" => "1"])
        @test length(data_headers) == 1
        @test data_headers["x-test"] == "1"
        @test get(data_headers, "missing", "fallback") == "fallback"
        @test haskey(data_headers, "X-Test")
        @test collect(keys(data_headers)) == ["X-Test"]
        @test collect(pairs(data_headers)) == ["X-Test" => "1"]

        vector_headers = InochiCore.Headers([SubString(backing, 1, 3) => SubString(backing, 4, 6)])
        @test length(vector_headers) == 1
        @test vector_headers["foo"] == "Bar"
        @test get(vector_headers, "missing", "fallback") == "fallback"
        @test haskey(vector_headers, "FOO")
        @test collect(keys(vector_headers)) == [SubString(backing, 1, 3)]
        @test collect(pairs(vector_headers)) == [SubString(backing, 1, 3) => SubString(backing, 4, 6)]
        @test collect(vector_headers) == [SubString(backing, 1, 3) => SubString(backing, 4, 6)]
        @test InochiCore.getheaders(vector_headers, "foo") == ["Bar"]
        @test InochiCore._ascii_case_equal("Foo", "fOO")
        @test !InochiCore._ascii_case_equal("Foo", "bar")
        @test_throws ArgumentError InochiCore._validate_header!("bad name", "x")
        @test_throws ArgumentError InochiCore._validate_header!("X-Test", "bad\x01")

        source = "Foo: bar\nBaz: qux"
        source_headers = InochiCore.Headers(source, [(1, 3, 6, 8), (10, 12, 15, 17)])
        @test length(source_headers) == 2
        @test source_headers["foo"] == "bar"
        @test source_headers["BAZ"] == "qux"
        @test get(source_headers, "missing", "fallback") == "fallback"
        @test haskey(source_headers, "baz")
        @test collect(source_headers) == [SubString(source, 1, 3) => SubString(source, 6, 8), SubString(source, 10, 12) => SubString(source, 15, 17)]
        @test InochiCore.getheaders(source_headers, "baz") == ["qux"]
        @test getfield(source_headers, :source) === source

        copy_headers = copy(source_headers)
        @test copy_headers != nothing
        empty!(copy_headers)
        @test length(copy_headers) == 0

        source_headers["Baz"] = "changed"
        @test getfield(source_headers, :source) === nothing
        @test source_headers["baz"] == "changed"
        delete!(source_headers, "Foo")
        @test !haskey(source_headers, "Foo")
        delete!(source_headers, "Missing")
        appendheader!(source_headers, "Set-Cookie" => "a=b")
        appendheader!(source_headers, "Set-Cookie" => "c=d")
        @test InochiCore.getheaders(source_headers, "set-cookie") == ["a=b", "c=d"]

        source_headers["bad name"] = "x"
        @test source_headers["bad name"] == "x"
        source_headers["X"] = "bad\0"
        @test source_headers["X"] == "bad\0"

        source_headers2 = InochiCore.Headers(source, [(1, 3, 6, 8)])
        @test getfield(source_headers2, :source) === source
        delete!(source_headers2, "Foo")
        @test getfield(source_headers2, :source) === nothing
        @test length(source_headers2) == 0
        @test InochiCore._normalize_headers(["A" => "1", "B" => "2"]) isa InochiCore.Headers
        @test length(InochiCore._normalize_headers(["A" => "1", "B" => "2"])) == 2
        @test InochiCore._header_lookup_key(source_headers2, "Foo") === nothing
        @test InochiCore._header_lookup_key(source_headers2, "Missing") === nothing
        @test InochiCore._validate_header_name("X-Test") == "X-Test"
        @test InochiCore._validate_header_value("abc\tdef") == "abc\tdef"
    end

    @testset "Request" begin
        @test occursin("max_content_size", sprint(showerror, InochiCore.PayloadTooLargeError()))

        empty_lazy = InochiCore.LazyBody("abc", 1, 0)
        @test InochiCore.bodylength(empty_lazy) == 0
        @test InochiCore.bodytext(empty_lazy) == ""
        @test InochiCore.bodybytes(empty_lazy) == UInt8[]
        @test empty_lazy.cache !== nothing

        nonempty_lazy = InochiCore.LazyBody("hello", 1, 5)
        @test InochiCore.bodylength(nonempty_lazy) == 5
        @test InochiCore.bodytext(nonempty_lazy) == "hello"
        @test String(InochiCore.bodybytes(nonempty_lazy)) == "hello"
        @test nonempty_lazy.cache !== nothing
        @test InochiCore.bodybytes(UInt8[0x61, 0x62]) == UInt8[0x61, 0x62]
        @test InochiCore.bodytext(UInt8[0x61, 0x62]) == "ab"
        @test InochiCore.bodylength(UInt8[0x61, 0x62]) == 2
        @test InochiCore.PayloadTooLargeError() isa Exception
        @test sprint(showerror, InochiCore.PayloadTooLargeError()) == "HTTP request body exceeds max_content_size"

        headers = InochiCore.Headers(["X-Test" => "1"])
        req1 = InochiCore.Request(SubString("GET", 1, 3), SubString("/sub", 1, 4), 1, headers, empty_lazy)
        @test req1.method == "GET"
        @test req1.target == "/sub"
        @test req1.version == 1
        @test req1.headers["x-test"] == "1"
        @test req1.body === empty_lazy

        req2 = InochiCore.Request("POST", "/dict", Dict("A" => "1"), "abc")
        @test req2.headers["a"] == "1"
        @test String(InochiCore.bodytext(req2)) == "abc"

        req3 = InochiCore.Request("POST", "/vec", ["B" => "2"], UInt8[0x61, 0x62])
        @test req3.headers["b"] == "2"
        @test String(InochiCore.bodytext(req3)) == "ab"

        req4 = InochiCore.Request(SubString("POST", 1, 4), SubString("/ver", 1, 4), 2, Dict("C" => "3"), "xyz")
        @test req4.version == 2
        @test req4.headers["c"] == "3"

        req5 = InochiCore.Request(SubString("POST", 1, 4), SubString("/ver", 1, 4), 2, Dict("D" => "4"), UInt8[0x78, 0x79])
        @test req5.headers["d"] == "4"
        @test req5.body == UInt8[0x78, 0x79]

        req6 = InochiCore.Request("GET", "/default")
        @test req6.version == 1
        req7 = InochiCore.Request("GET", "/headers", 1, InochiCore.Headers(["E" => "5"]), empty_lazy)
        @test req7.method == "GET"
        @test req7.target == "/headers"
        @test req7.headers["e"] == "5"
        @test req7.body === empty_lazy
        @test InochiCore.Request("GET", "/default").version == 1
        @test InochiCore.Request("GET", "/default", InochiCore.Headers()).body == UInt8[]
        @test InochiCore.Request("GET", "/default", Dict("F" => "6")).headers["f"] == "6"
        @test InochiCore.Request("GET", "/default", ["G" => "7"]).headers["g"] == "7"
        @test InochiCore.Request("GET", "/default", ["J" => "10"], "abc").body == Vector{UInt8}(codeunits("abc"))
        @test InochiCore.Request("GET", "/default", 1, Dict("H" => "8"), UInt8[0x39]).version == 1
        @test InochiCore.Request("GET", "/default", 1, ["I" => "9"], "xyz").headers["i"] == "9"

        bytes_upper = Vector{UInt8}(codeunits("Foo"))
        bytes_lower = Vector{UInt8}(codeunits("foo"))
        @test InochiCore._ascii_case_equal(bytes_upper, 1, 3, "foo")
        @test InochiCore._ascii_case_equal(bytes_lower, 1, 3, "FOO")
        @test InochiCore._parse_uint(Vector{UInt8}(codeunits("123")), 1, 3) == 123
        @test InochiCore._parse_uint(Vector{UInt8}(codeunits(" 123 ")), 2, 4) == 123

        raw = "POST /trim HTTP/1.1\r\nHost: example.com\r\nContent-Length:   11  \r\nContent-Type: text/plain\r\n\r\nhello world"
        parsed = parse_raw_request(raw)
        @test parsed.body isa InochiCore.LazyBody
        @test InochiCore.bodylength(parsed) == 11
        @test InochiCore.bodytext(parsed) == "hello world"
        @test String(InochiCore.bodybytes(parsed)) == "hello world"

        cl_state = InochiCore._RequestState()
        cl_state.request_bytes = Vector{UInt8}(codeunits("Content-Length:   11  "))
        cl_state.header_ranges = [(1, 14, 17, 22)]
        @test InochiCore._header_value_range(cl_state, "Content-Length") == (17, 22)
        @test InochiCore._header_value_range(cl_state, "Missing") === nothing
        @test InochiCore._content_length(cl_state) == 11

        bad_parser = InochiCore.LlhttpWrapper.Parser(InochiCore.LlhttpWrapper.HTTP_REQUEST; settings = InochiCore._parser_settings())
        bad_state_ref = Ref(InochiCore._RequestState())
        InochiCore.LlhttpWrapper.set_userdata!(bad_parser, Base.pointer_from_objref(bad_state_ref))
        malformed = Vector{UInt8}(codeunits("GET / HTTP/1.1\r\nBad Header\r\n\r\n"))
        GC.@preserve bad_state_ref bad_parser malformed begin
            code = InochiCore.LlhttpWrapper.execute!(bad_parser, malformed)
            @test code != InochiCore.LlhttpWrapper.HPE_OK
            err = InochiCore._parse_error(bad_parser, code)
            @test occursin("HTTP parse error", err.msg)
            @test InochiCore._on_reset(Base.unsafe_convert(Ptr{InochiCore.LlhttpWrapper.llhttp_t}, bad_parser)) == 0
        end

        limited_app = App()
        limited_app.config["max_content_size"] = 2
        limited_ctx = Context(limited_app, InochiCore.Request("POST", "/x", ["Content-Type" => "text/plain"], "hello"))
        @test_throws InochiCore.PayloadTooLargeError Inochi.request_body_text(limited_ctx)
        @test_throws InochiCore.PayloadTooLargeError Inochi.request_body_bytes(limited_ctx)

        with_tcp_pair() do sock, client, server
            close(client)
            @test InochiCore._read_chunk(sock) == UInt8[]
        end

        with_tcp_pair() do sock, client, server
            raw = "POST /read HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\n\r\nhello"
            write(client, Vector{UInt8}(codeunits(raw)))
            flush(client)
            request = InochiCore._read_request(sock)
            @test request.method == "POST"
            @test request.target == "/read"
            @test request.version == 1
            @test request.headers["host"] == "example.com"
            @test String(InochiCore.bodytext(request)) == "hello"
            close(client)
        end

        with_tcp_pair() do sock, client, server
            close(client)
            parser = InochiCore.LlhttpWrapper.Parser(InochiCore.LlhttpWrapper.HTTP_REQUEST; settings = InochiCore._parser_settings())
            state_ref = Ref(InochiCore._RequestState())
            InochiCore.LlhttpWrapper.set_userdata!(parser, Base.pointer_from_objref(state_ref))
            GC.@preserve state_ref parser begin
                @test InochiCore._next_request!(sock, parser, state_ref) === nothing
            end
        end
    end

    @testset "Response" begin
        dict_response = InochiCore.Response(201, Dict("X-Test" => "1"), "body")
        vector_response = InochiCore.Response(202, ["X-Test" => "2"], UInt8[0x62, 0x6f, 0x64, 0x79])
        headers_response = InochiCore.Response(203, InochiCore.Headers(["X-Test" => "3"]))
        @test dict_response.status == 201
        @test vector_response.status == 202
        @test headers_response.status == 203
        @test InochiCore.Response(200, Dict("X-Test" => "1"), UInt8[0x61]).body == UInt8[0x61]
        @test InochiCore.Response(200, ["X-Test" => "1"], "ok").body == "ok"
        @test InochiCore.Response(200, ["X-Test" => "1"], UInt8[0x6f, 0x6b]).body == UInt8[0x6f, 0x6b]
        @test InochiCore.Response(200, ["X-Test" => "1"]).body == ""
        @test InochiCore.Response(200, "ok").body == "ok"
        @test InochiCore.Response(200, UInt8[0x6f, 0x6b]).body == UInt8[0x6f, 0x6b]
        @test InochiCore.Response(200, InochiCore.Headers(["X-Test" => "1"]), "ok").body == "ok"
        @test InochiCore.Response(200, InochiCore.Headers(["X-Test" => "1"]), UInt8[0x6f, 0x6b]).body == UInt8[0x6f, 0x6b]
        @test InochiCore.Response(200, InochiCore.Headers(["X-Test" => "1"])).body == ""
        @test InochiCore.response_body_length("abc") == 3
        @test InochiCore.response_body_length(UInt8[0x61, 0x62]) == 2
        status_io = IOBuffer()
        InochiCore._write_status_line(status_io, 200)
        @test startswith(String(take!(status_io)), "HTTP/1.1 200")
        @test InochiCore._default_error_response(InochiCore.PayloadTooLargeError()).status == 413
        @test InochiCore._default_error_response(ErrorException("HTTP parse error (boom)")).status == 400
        @test InochiCore._default_error_response(ErrorException("something else")).status == 500
        @test InochiCore._normalize_host("127.0.0.1") == Sockets.getaddrinfo("127.0.0.1")

        io = IOBuffer()
        InochiCore._write_response(io, InochiCore.Response(200, InochiCore.Headers(["X-Test" => "1"]), "ok"))
        written = String(take!(io))
        @test startswith(written, "HTTP/1.1 200")
        @test occursin("Content-Length: 2", written)
        @test occursin("Connection: close", written)

        io2 = IOBuffer()
        InochiCore._write_response(io2, InochiCore.Response(200, InochiCore.Headers(["Content-Length" => "2", "Connection" => "keep-alive"]), UInt8[0x6f, 0x6b]))
        written2 = String(take!(io2))
        @test occursin("Content-Length: 2", written2)
        @test occursin("Connection: keep-alive", written2)
        io3 = IOBuffer()
        InochiCore._write_response(io3, InochiCore.Response(200, Dict("X-Test" => "1"), "ok"))
        written3 = String(take!(io3))
        @test occursin("X-Test: 1", written3)

        @test InochiCore._default_error_response(InochiCore.PayloadTooLargeError()).status == 413
        @test InochiCore._default_error_response(ErrorException("HTTP parse error (boom)")).status == 400
        @test InochiCore._default_error_response(ErrorException("something else")).status == 500

        with_tcp_pair() do sock, client, server
            @test_throws ArgumentError InochiCore._handle_connection(sock, req -> Response(200, Headers()); allow_http1 = false, allow_http2 = false)
        end

        with_tcp_pair() do sock, client, server
            handler_calls = Ref(0)
            handler = req -> begin
                handler_calls[] += 1
                Response(200, Headers(["X-Test" => "1"]), "ok")
            end
            @async InochiCore._handle_http1_connection(sock, handler)
            write(client, Vector{UInt8}(codeunits("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")))
            flush(client)
            @test handler_calls[] == 1
            sleep(0.05)
            response = readavailable(client)
            @test occursin("HTTP/1.1 200 OK", String(response))
            close(client)
        end

        with_tcp_pair() do sock, client, server
            close(client)
            @test isnothing(InochiCore._handle_connection(sock, req -> Response(200, Headers()); allow_http1 = true, allow_http2 = true))
        end

        with_tcp_pair() do sock, client, server
            write(client, Vector{UInt8}(codeunits("NOT-H2")))
            flush(client)
            @test isnothing(InochiCore._handle_connection(sock, req -> Response(200, Headers()); allow_http1 = false, allow_http2 = true))
        end

        with_tcp_pair() do sock, client, server
            handler_calls = Ref(0)
            handler = req -> begin
                handler_calls[] += 1
                Response(200, Headers(["X-Test" => "1"]), "ok")
            end
            @async InochiCore._handle_connection(sock, handler; allow_http1 = true, allow_http2 = false)
            write(client, Vector{UInt8}(codeunits("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")))
            flush(client)
            @test handler_calls[] == 1
            sleep(0.05)
            response = readavailable(client)
            @test occursin("HTTP/1.1 200 OK", String(response))
            close(client)
        end

        server = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
        port = Sockets.getsockname(server)[2]
        calls = Ref(0)
        task = @async InochiCore.serve(req -> begin
            calls[] += 1
            Response(200, Headers(["X-Test" => "1"]), "ok")
        end, server; allow_http1 = true, allow_http2 = false)
        client = Sockets.connect(Sockets.IPv4(127, 0, 0, 1), port)
        write(client, Vector{UInt8}(codeunits("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")))
        flush(client)
        @test calls[] == 1
        sleep(0.05)
        response = readavailable(client)
        @test occursin("HTTP/1.1 200 OK", String(response))
        close(client)
        close(server)
        wait(task)

        with_tcp_pair() do sock, client, server
            callbacks = NghttpWrapper.callbacks_new()
            option = NghttpWrapper.option_new()
            session = NghttpWrapper.Session(:client; callbacks=callbacks, option=option)
            try
                preface = NghttpWrapper.session_mem_send_bytes(session)
                NghttpWrapper.submit_request(session, [
                    ":method" => "GET",
                    ":path" => "/h2",
                    ":scheme" => "http",
                    ":authority" => "127.0.0.1:8080",
                ])
                bytes = vcat(preface, NghttpWrapper.session_mem_send_bytes(session))
                task = @async InochiCore._handle_connection(sock, req -> Response(204, Headers()); allow_http1 = false, allow_http2 = true)
                write(client, bytes)
                flush(client)
                sleep(0.2)
                closewrite(client)
                @test fetch(task) === nothing
            finally
                NghttpWrapper.session_del!(session)
                NghttpWrapper.option_del!(option)
                NghttpWrapper.callbacks_del!(callbacks)
            end
        end
    end

    @testset "Context Helpers" begin
        ctx = Context(App(), InochiCore.Request("GET", "/cookie", ["Cookie" => "session=abc; theme=dark"]))
        @test cookie(ctx, "session", "missing") == "abc"
        @test cookie(ctx, "missing", "fallback") == "fallback"
        @test cookie(ctx)["theme"] == "dark"
        @test Inochi.request_content_type(Context(App(), InochiCore.Request("GET", "/"))) == ""

        state_ctx = Context(App(), InochiCore.Request("GET", "/state"))
        @test get(state_ctx, :missing, "fallback") == "fallback"
        @test set!(state_ctx, :seen, true) === true
        @test get(state_ctx, :seen, false) === true

        response_ctx = Context(App(), InochiCore.Request("GET", "/response"))
        response!(response_ctx, InochiCore.Response(201, ["X-Direct" => "1"], "raw"))
        @test response_ctx.status == 201
        @test String(response_ctx.body) == "raw"
        @test getfield(response_ctx, :response) !== nothing

        source_ctx = Context(App(), InochiCore.Request("GET", "/source"))
        source_ctx.headers = InochiCore.Headers(["X-Source" => "1"])
        source_ctx.cookies_out = HTTP.Cookies.Cookie[]
        source_ctx.state = Dict{Symbol,Any}(:a => 1)
        source_ctx.content_type = "text/plain"
        source_ctx.query_params = Dict("q" => "1")
        source_ctx.form_params = Dict("f" => "2")
        source_ctx.multipart_parts = HTTP.Multipart[]
        source_ctx.varies_on_cookie = true
        response!(source_ctx, InochiCore.Response(202, ["X-Resp" => "1"], "body"))

        copied_ctx = Context(App(), InochiCore.Request("GET", "/dest"))
        Inochi.apply_result!(copied_ctx, source_ctx)
        @test copied_ctx.status == 202
        @test copied_ctx.headers["X-Source"] == "1"
        @test copied_ctx.body == "body"
        @test copied_ctx.state[:a] == 1
        @test copied_ctx.content_type == "text/plain"
        @test copied_ctx.query_params["q"] == "1"
        @test copied_ctx.form_params["f"] == "2"
        @test isempty(copied_ctx.multipart_parts)
        @test copied_ctx.varies_on_cookie
        @test getfield(copied_ctx, :response) !== nothing

        vary_ctx = Context(App(), InochiCore.Request("GET", "/vary"))
        vary_ctx.headers = InochiCore.Headers(["Vary" => "Accept"])
        vary_ctx.varies_on_cookie = true
        Inochi.apply_default_headers(vary_ctx)
        @test vary_ctx.headers["Vary"] == "Accept, Origin, Cookie"
        @test Inochi.merge_vary("Origin, origin", "Cookie") == "Origin, Cookie"
        @test Inochi.merge_vary("Origin", "origin") == "Origin"

        oversize_ctx = Context(App(), InochiCore.Request("POST", "/oversize", ["Content-Type" => "text/plain"], "hello"))
        oversize_ctx.app.config["max_content_size"] = 1
        @test_throws InochiCore.PayloadTooLargeError Inochi.request_body_text(oversize_ctx)
        @test_throws InochiCore.PayloadTooLargeError Inochi.request_body_bytes(oversize_ctx)

        rt_view = Inochi.RouteParamsView(("id", "name"), (SubString("42", 1, 2), SubString("alice", 1, 5)))
        @test rt_view["id"] == "42"
        @test get(rt_view, "name", "missing") == "alice"
        @test get(rt_view, "missing", "fallback") == "fallback"
        @test haskey(rt_view, "name")
        @test !haskey(rt_view, "missing")
        @test_throws KeyError rt_view["missing"]

        mw_params = Inochi.MiddlewareParams(SubString("tail", 1, 4))
        @test mw_params["*"] == "tail"
        @test get(mw_params, "*", "missing") == "tail"
        @test get(mw_params, "missing", "fallback") == "fallback"
        @test haskey(mw_params, "*")
        @test_throws KeyError mw_params["id"]
    end

    @testset "Routing Helpers" begin
        @test Inochi.matched_middleware_routes(nothing) === Inochi.EMPTY_MIDDLEWARE_ROUTES
        @test Inochi.route_static_prefix("/") == "/"
        @test Inochi.route_static_prefix("/a/:id/b") == "/a"
        @test Inochi.path_prefix_matches("/a/b", "/a")
        @test !Inochi.path_prefix_matches("/a", "/a/b")
        @test Inochi.route_prefix_may_match("/a", "/a")
        @test Inochi.route_prefix_may_match("/a", "/a/b")
        @test Inochi.middleware_tail("/admin/users", "/admin") == "users"
        @test Inochi.middleware_tail("/admin", "/admin") == ""
        @test Inochi.middleware_tail("/admin/users", "/other") === nothing

        route = Inochi.MiddlewareRoute(ctx -> ctx, "/*", "/", 1)
        matcher = Inochi.MiddlewareMatcher([route], 1, Inochi.empty_middleware_matcher)
        collected = Inochi.collect_middlewares(matcher, "/anything", nothing)
        @test length(collected) == 1
        @test collected[1].path == "/*"

        routes = [Inochi.MiddlewareRoute(ctx -> ctx, "/mw", "/mw", 1)]
        collected2 = Inochi.collect_middlewares(routes, "/mw/path", nothing)
        @test length(collected2) == 1
        @test collected2[1].path == "/mw"

        error_app = App()
        error_app.error_handler = (ctx, err) -> nothing
        error_ctx = Context(error_app, InochiCore.Request("GET", "/err"))
        Inochi.handle_error(error_app, error_ctx, InochiCore.PayloadTooLargeError())
        @test error_ctx.status == 413
        @test String(error_ctx.body) == "Payload Too Large"
    end

    @testset "Wrapper Includes" begin
        wrapper_mod = Module(:CoverageWrappers)
        Core.eval(wrapper_mod, :(using Inochi))
        Core.eval(wrapper_mod, :(include(path) = Base.include(@__MODULE__, path)))
        Base.include(wrapper_mod, joinpath(@__DIR__, "..", "src", "Inochi.jl"))
        @test isdefined(wrapper_mod, :Inochi)
    end

end
