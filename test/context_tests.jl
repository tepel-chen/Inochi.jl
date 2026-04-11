using Dates

@testset "Context" begin
    app = App()

    get(app, "/ctx/:id") do ctx
        set!(ctx, :seen, true)
        text(ctx, "id=" * ctx.params["id"]; status = 201)
    end

    use(app, "/ctx/*") do ctx
        header!(ctx, "X-Middleware", "on")
        next(ctx)
    end

    get(app, "/ctx/html") do ctx
        html(ctx, "<h1>ok</h1>")
    end

    get(app, "/ctx/redirect") do ctx
        redirect(ctx, "/next")
    end

    get(app, "/ctx/raw") do ctx
        header!(ctx, "X-Ignored", "yes")
        setcookie(ctx, "session", "abc"; path = "/")
        InochiCore.Response(202, ["X-Direct" => "1"], "raw")
    end

    response = Inochi.dispatch(app, InochiCore.Request("GET", "/ctx/42"))
    @test response.status == 201
    @test String(response.body) == "id=42"
    @test response.headers["X-Middleware"] == "on"

    state_ctx = Context(app, InochiCore.Request("GET", "/ctx/1"))
    @test state_ctx.state === nothing
    @test set!(state_ctx, :seen, true) === true
    @test state_ctx.state !== nothing
    @test get(state_ctx, :seen, false) === true

    html_response = Inochi.dispatch(app, InochiCore.Request("GET", "/ctx/html"))
    @test html_response.status == 200
    @test String(html_response.body) == "<h1>ok</h1>"
    @test html_response.headers["Content-Type"] == "text/html; charset=utf-8"

    redirect_response = Inochi.dispatch(app, InochiCore.Request("GET", "/ctx/redirect"))
    @test redirect_response.status == 303
    @test redirect_response.headers["Location"] == "/next"
    @test String(redirect_response.body) == ""

    raw_response = Inochi.dispatch(app, InochiCore.Request("GET", "/ctx/raw"))
    @test raw_response.status == 202
    @test String(raw_response.body) == "raw"
    @test raw_response.headers["X-Direct"] == "1"
    @test get(raw_response.headers, "X-Ignored", nothing) === nothing
    @test get(raw_response.headers, "X-Middleware", nothing) === nothing
    @test isempty(InochiCore.getheaders(raw_response.headers, "Set-Cookie"))
    @test get(raw_response.headers, "Server", nothing) === nothing
    @test get(raw_response.headers, "Date", nothing) === nothing
    @test get(raw_response.headers, "Vary", nothing) === nothing
end

@testset "Date Header Cache" begin
    timestamp = DateTime(2024, 1, 1, 0, 0, 0)
    first = Inochi.http_date(timestamp)
    second = Inochi.http_date(timestamp)

    @test first == second
    @test occursin(HTTP_DATE_PATTERN, first)
end

@testset "Rendering" begin
    app = App()
    app.renderer = (template, data) -> replace(template, "{{name}}" => string(data["name"]))

    get(app, "/inline") do ctx
        render_text(ctx, "hello {{name}}", Dict("name" => "inochi"))
    end

    inline_response = Inochi.dispatch(app, InochiCore.Request("GET", "/inline"))
    @test inline_response.status == 200
    @test String(inline_response.body) == "hello inochi"
    @test inline_response.headers["Content-Type"] == "text/html; charset=utf-8"

    mktempdir() do tmpdir
        app.views = tmpdir
        write(joinpath(tmpdir, "hello.mustache"), "<h1>{{name}}</h1>")

        get(app, "/file") do ctx
            render(ctx, "hello.mustache", Dict("name" => "Inochi"))
        end

        file_response = Inochi.dispatch(app, InochiCore.Request("GET", "/file"))
        @test file_response.status == 200
        @test String(file_response.body) == "<h1>Inochi</h1>"

        bad_ctx = Context(app, InochiCore.Request("GET", "/"))
        @test_throws ArgumentError render(bad_ctx, "../secret.mustache", Dict("name" => "x"))
        @test_throws Exception bad_ctx.render
    end

    fallback_views_root = joinpath(Inochi.executable_root(), "views")
    mkpath(fallback_views_root)
    fallback_template = joinpath(fallback_views_root, "fallback.mustache")
    write(fallback_template, "<p>{{name}}</p>")
    try
        fallback_views_app = App()
        fallback_views_app.renderer = (template, data) -> replace(template, "{{name}}" => string(data["name"]))

        get(fallback_views_app, "/fallback") do ctx
            render(ctx, "fallback.mustache", Dict("name" => "fallback"))
        end

        fallback_views_response = Inochi.dispatch(fallback_views_app, InochiCore.Request("GET", "/fallback"))
        @test fallback_views_response.status == 200
        @test String(fallback_views_response.body) == "<p>fallback</p>"
        @test Inochi.resolve_views_root(Context(App(), InochiCore.Request("GET", "/"))) == joinpath(Inochi.executable_root(), "views")
    finally
        isfile(fallback_template) && rm(fallback_template; force = true)
    end

    mktempdir() do tmpdir
        cd(tmpdir) do
            mkpath("views")
            write(joinpath("views", "default.mustache"), "<p>{{name}}</p>")

            default_views_app = App()
            default_views_app.renderer = (template, data) -> replace(template, "{{name}}" => string(data["name"]))
            default_views_app.views = joinpath(pwd(), "views")

            get(default_views_app, "/default-views") do ctx
                render(ctx, "default.mustache", Dict("name" => "default"))
            end

            default_views_response = Inochi.dispatch(default_views_app, InochiCore.Request("GET", "/default-views"))
            @test default_views_response.status == 200
            @test String(default_views_response.body) == "<p>default</p>"
        end
    end

    file_renderer_app = App()
    file_renderer_app.renderer = (_, _) -> error("render_text fallback should not be used")
    file_renderer_app.file_renderer = (filepath, data) -> begin
        basename(filepath) == "hello.mustache" || error("unexpected filepath")
        "<p>" * string(data["name"]) * "</p>"
    end

    mktempdir() do tmpdir
        file_renderer_app.views = tmpdir
        write(joinpath(tmpdir, "hello.mustache"), "ignored")
        get(file_renderer_app, "/file-renderer") do ctx
            render(ctx, "hello.mustache", Dict("name" => "cached"))
        end

        response = Inochi.dispatch(file_renderer_app, InochiCore.Request("GET", "/file-renderer"))
        @test response.status == 200
        @test String(response.body) == "<p>cached</p>"
    end
end

@testset "Request Parsers" begin
    function parse_inochi_request(raw::String)
        bytes = Vector{UInt8}(codeunits(raw))
        state_ref = Ref(InochiCore._RequestState())
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

    app = App()

    post(app, "/text") do ctx
        text(ctx, reqtext(ctx))
    end

    post(app, "/json") do ctx
        payload = reqjson(ctx)
        text(ctx, string(payload["name"], ":", payload["count"]))
    end

    post(app, "/form") do ctx
        form = reqform(ctx)
        text(ctx, string(form["x"], ":", form["y"]))
    end

    get(app, "/query") do ctx
        query = reqquery(ctx)
        text(ctx, string(query["page"], ":", query["q"]))
    end

    response1 = Inochi.dispatch(app, InochiCore.Request("POST", "/text", ["Content-Type" => "text/plain; charset=utf-8"], "hello"))
    @test response1.status == 200
    @test String(response1.body) == "hello"

    response2 = Inochi.dispatch(app, InochiCore.Request("POST", "/json", ["Content-Type" => "application/json"], "{\"name\":\"alice\",\"count\":3}"))
    @test response2.status == 200
    @test String(response2.body) == "alice:3"

    response3 = Inochi.dispatch(app, InochiCore.Request("POST", "/form", ["Content-Type" => "application/x-www-form-urlencoded"], "x=10&y=hello"))
    @test response3.status == 200
    @test String(response3.body) == "10:hello"

    response4 = Inochi.dispatch(app, InochiCore.Request("GET", "/query?page=2&q=inochi"))
    @test response4.status == 200
    @test String(response4.body) == "2:inochi"

    cached_ctx = Context(app, InochiCore.Request("GET", "/cache?page=1&q=hello", ["Content-Type" => "application/x-www-form-urlencoded"], "x=10&y=hello"))
    @test reqquery(cached_ctx) === reqquery(cached_ctx)
    @test reqform(cached_ctx) === reqform(cached_ctx)
    @test Inochi.request_content_type(cached_ctx) === Inochi.request_content_type(cached_ctx)

    lazy_request = parse_inochi_request("POST /lazy HTTP/1.1\r\nHost: example.com\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nhello world")
    @test lazy_request.body isa InochiCore.LazyBody
    @test lazy_request.body.cache === nothing
    lazy_ctx = Context(app, lazy_request)
    lazy_text = reqtext(lazy_ctx)
    @test lazy_text isa String
    @test lazy_text == "hello world"
    @test lazy_request.body.cache === nothing
    @test String(InochiCore.bodybytes(lazy_request)) == "hello world"
    @test lazy_request.body.cache !== nothing

    limited_state_ref = Ref(InochiCore._RequestState(4))
    limited_parser = InochiCore.LlhttpWrapper.Parser(InochiCore.LlhttpWrapper.HTTP_REQUEST; settings = InochiCore._parser_settings())
    InochiCore.LlhttpWrapper.set_userdata!(limited_parser, Base.pointer_from_objref(limited_state_ref))
    limited_raw = Vector{UInt8}(codeunits("POST /limited HTTP/1.1\r\nHost: example.com\r\nContent-Length: 11\r\n\r\nhello world"))
    GC.@preserve limited_state_ref limited_parser limited_raw begin
        limited_code = InochiCore.LlhttpWrapper.execute!(limited_parser, limited_raw)
        @test limited_code == InochiCore.LlhttpWrapper.HPE_PAUSED
        @test limited_state_ref[].body_too_large
        @test limited_state_ref[].body_start == 0
        @test isempty(limited_state_ref[].completed)
    end

    parser_app = App()

    bad_text_ctx = Context(parser_app, InochiCore.Request("POST", "/text", ["Content-Type" => "application/json"], "\"hello\""))
    @test_throws ArgumentError reqtext(bad_text_ctx)
    @test_throws Exception bad_text_ctx.reqtext

    bad_json_ctx = Context(parser_app, InochiCore.Request("POST", "/json", ["Content-Type" => "text/plain"], "{\"name\":\"alice\"}"))
    @test_throws ArgumentError reqjson(bad_json_ctx)
    @test_throws Exception bad_json_ctx.reqjson

    bad_form_ctx = Context(parser_app, InochiCore.Request("POST", "/form", ["Content-Type" => "application/json"], "x=10"))
    @test_throws ArgumentError reqform(bad_form_ctx)

    charset_json_ctx = Context(parser_app, InochiCore.Request("POST", "/json", ["Content-Type" => "application/json; charset=utf-8"], "{\"name\":\"bob\",\"count\":4}"))
    @test reqjson(charset_json_ctx)["name"] == "bob"

    multipart_body = join([
        "--boundary123",
        "Content-Disposition: form-data; name=\"title\"",
        "",
        "hello",
        "--boundary123",
        "Content-Disposition: form-data; name=\"image\"; filename=\"pixel.jpg\"",
        "Content-Type: image/jpeg",
        "",
        "binary-image-data",
        "--boundary123--",
        "",
    ], "\r\n")
    multipart_req = InochiCore.Request(
        "POST",
        "/upload",
        [
            "Content-Type" => "multipart/form-data; boundary=boundary123",
            "Content-Length" => string(length(codeunits(multipart_body))),
        ],
        Vector{UInt8}(multipart_body),
    )
    multipart_ctx = Context(parser_app, multipart_req)
    multipart_parts = reqmultipart(multipart_ctx)
    @test length(multipart_parts) == 2
    @test multipart_parts[1].name == "title"
    @test String(read(multipart_parts[1].data)) == "hello"
    file_part = reqfile(multipart_ctx; name = "image")
    @test file_part !== nothing
    @test file_part.filename == "pixel.jpg"
    @test file_part.name == "image"
    @test file_part.contenttype == "image/jpeg"
    @test reqfile(multipart_ctx; name = "missing") === nothing
    ctx_file_part = reqfile(multipart_ctx; name = "image")
    @test ctx_file_part !== nothing
    @test ctx_file_part.filename == "pixel.jpg"
    @test length(reqmultipart(multipart_ctx)) == 2
    @test reqmultipart(multipart_ctx) === reqmultipart(multipart_ctx)

    bad_multipart_ctx = Context(parser_app, InochiCore.Request("POST", "/upload", ["Content-Type" => "application/json"], "{}"))
    @test_throws ArgumentError reqmultipart(bad_multipart_ctx)
end

@testset "Cookies" begin
    app = App()

    get(app, "/cookie") do ctx
        text(ctx, cookie(ctx, "session", "missing") * ":" * cookie(ctx)["theme"])
    end

    get(app, "/set-cookie") do ctx
        setcookie(ctx, "session", "abc"; path = "/", httponly = true)
        setcookie(ctx, "theme", "dark"; maxage = 60)
        text(ctx, "ok")
    end

    req = InochiCore.Request("GET", "/cookie", ["Cookie" => "session=abc; theme=dark"])
    response = Inochi.dispatch(app, req)
    @test response.status == 200
    @test String(response.body) == "abc:dark"
    @test response.headers["Vary"] == "Origin, Cookie"

    response2 = Inochi.dispatch(app, InochiCore.Request("GET", "/set-cookie"))
    set_cookie_headers = String.(InochiCore.getheaders(response2.headers, "Set-Cookie"))
    @test response2.status == 200
    @test String(response2.body) == "ok"
    @test response2.headers["Vary"] == "Origin"
    @test length(set_cookie_headers) == 2
    @test any(header -> occursin("session=abc", header), set_cookie_headers)
    @test any(header -> occursin("HttpOnly", header), set_cookie_headers)
    @test any(header -> occursin("theme=dark", header), set_cookie_headers)
    @test any(header -> occursin("Max-Age=60", header), set_cookie_headers)
end

@testset "Secure Cookies" begin
    app = App()
    app.config["secret"] = "top-secret"

    get(app, "/secure-set") do ctx
        set_secure_cookie(ctx, "session", "abc123"; path = "/", httponly = true)
        text(ctx, "ok")
    end

    get(app, "/secure-read") do ctx
        text(ctx, string(secure_cookie(ctx, "session"; default = "missing")))
    end

    response1 = Inochi.dispatch(app, InochiCore.Request("GET", "/secure-set"))
    cookie_header = only(String.(InochiCore.getheaders(response1.headers, "Set-Cookie")))
    secure_value = first(split(cookie_header, ';'; limit = 2))
    @test occursin("session=", secure_value)

    req = InochiCore.Request("GET", "/secure-read", ["Cookie" => secure_value])
    response2 = Inochi.dispatch(app, req)
    @test String(response2.body) == "abc123"
    @test response2.headers["Vary"] == "Origin, Cookie"

    tampered = secure_value[1:end-1] * (secure_value[end] == '0' ? "1" : "0")
    bad_req = InochiCore.Request("GET", "/secure-read", ["Cookie" => tampered])
    response3 = Inochi.dispatch(app, bad_req)
    @test String(response3.body) == "missing"
    @test response3.headers["Vary"] == "Origin, Cookie"

    invalid_payload = "a"
    invalid_signature = Inochi.secure_cookie_signature(app.config["secret"], invalid_payload)
    invalid_cookie = "session=$(invalid_payload).$(invalid_signature)"
    invalid_req = InochiCore.Request("GET", "/secure-read", ["Cookie" => invalid_cookie])
    response4 = Inochi.dispatch(app, invalid_req)
    @test response4.status == 500
    @test String(response4.body) == "Internal Server Error"

    app_without_config_secret = App()

    get(app_without_config_secret, "/secure-read") do ctx
        text(ctx, string(secure_cookie(ctx, "session"; default = "missing")))
    end

    missing_secret_req = InochiCore.Request("GET", "/secure-read", ["Cookie" => "session=YWJj.invalidsig"])
    missing_secret_response = Inochi.dispatch(app_without_config_secret, missing_secret_req)
    @test missing_secret_response.status == 500
    @test String(missing_secret_response.body) == "Internal Server Error"

    get(app_without_config_secret, "/secure-explicit-set") do ctx
        set_secure_cookie(ctx, "session", "explicit"; secret = "alt-secret", path = "/")
        text(ctx, "ok")
    end

    get(app_without_config_secret, "/secure-explicit-read") do ctx
        text(ctx, string(secure_cookie(ctx, "session"; secret = "alt-secret", default = "missing")))
    end

    explicit_set_response = Inochi.dispatch(app_without_config_secret, InochiCore.Request("GET", "/secure-explicit-set"))
    explicit_cookie_header = only(String.(InochiCore.getheaders(explicit_set_response.headers, "Set-Cookie")))
    explicit_value = first(split(explicit_cookie_header, ';'; limit = 2))
    explicit_read_response = Inochi.dispatch(
        app_without_config_secret,
        InochiCore.Request("GET", "/secure-explicit-read", ["Cookie" => explicit_value]),
    )
    @test explicit_set_response.status == 200
    @test explicit_read_response.status == 200
    @test String(explicit_read_response.body) == "explicit"
end

@testset "App Config" begin
    app = App()
    @test app.config["max_content_size"] == 4 * 1024 * 1024

    app.config["secret"] = "s3cr3t"
    @test app.config["secret"] == "s3cr3t"

    body_limited = App()
    body_limited.config["max_content_size"] = 4

    post(body_limited, "/json") do ctx
        json(ctx, reqjson(ctx))
    end

    response = Inochi.dispatch(
        body_limited,
        InochiCore.Request("POST", "/json", ["Content-Type" => "application/json"], "{\"hello\":1}"),
    )
    @test response.status == 413
    @test String(response.body) == "Payload Too Large"
end
