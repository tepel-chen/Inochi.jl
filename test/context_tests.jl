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
        HTTP.Response(202, ["X-Direct" => "1"], "raw")
    end

    response = Inochi.dispatch(app, HTTP.Request("GET", "/ctx/42"))
    @test response.status == 201
    @test String(response.body) == "id=42"
    @test HTTP.header(response, "X-Middleware") == "on"

    html_response = Inochi.dispatch(app, HTTP.Request("GET", "/ctx/html"))
    @test html_response.status == 200
    @test String(html_response.body) == "<h1>ok</h1>"
    @test HTTP.header(html_response, "Content-Type") == "text/html; charset=utf-8"

    redirect_response = Inochi.dispatch(app, HTTP.Request("GET", "/ctx/redirect"))
    @test redirect_response.status == 303
    @test HTTP.header(redirect_response, "Location") == "/next"
    @test String(redirect_response.body) == ""

    raw_response = Inochi.dispatch(app, HTTP.Request("GET", "/ctx/raw"))
    @test raw_response.status == 202
    @test String(raw_response.body) == "raw"
    @test HTTP.header(raw_response, "X-Direct") == "1"
    @test HTTP.header(raw_response, "X-Ignored", nothing) === nothing
    @test HTTP.header(raw_response, "X-Middleware", nothing) === nothing
    @test isempty(HTTP.headers(raw_response, "Set-Cookie"))
    @test HTTP.header(raw_response, "Server", nothing) === nothing
    @test HTTP.header(raw_response, "Date", nothing) === nothing
    @test HTTP.header(raw_response, "Vary", nothing) === nothing
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

    inline_response = Inochi.dispatch(app, HTTP.Request("GET", "/inline"))
    @test inline_response.status == 200
    @test String(inline_response.body) == "hello inochi"
    @test HTTP.header(inline_response, "Content-Type") == "text/html; charset=utf-8"

    mktempdir() do tmpdir
        app.views = tmpdir
        write(joinpath(tmpdir, "hello.mustache"), "<h1>{{name}}</h1>")

        get(app, "/file") do ctx
            render(ctx, "hello.mustache", Dict("name" => "Inochi"))
        end

        file_response = Inochi.dispatch(app, HTTP.Request("GET", "/file"))
        @test file_response.status == 200
        @test String(file_response.body) == "<h1>Inochi</h1>"

        bad_ctx = Context(app, HTTP.Request("GET", "/"))
        @test_throws ArgumentError render(bad_ctx, "../secret.mustache", Dict("name" => "x"))
        @test_throws Exception bad_ctx.render
    end

    fallback_views_root = joinpath(Inochi.executable_root(), "views")
    mkpath(fallback_views_root)
    write(joinpath(fallback_views_root, "fallback.mustache"), "<p>{{name}}</p>")

    fallback_views_app = App()
    fallback_views_app.renderer = (template, data) -> replace(template, "{{name}}" => string(data["name"]))

    get(fallback_views_app, "/fallback") do ctx
        render(ctx, "fallback.mustache", Dict("name" => "fallback"))
    end

    fallback_views_response = Inochi.dispatch(fallback_views_app, HTTP.Request("GET", "/fallback"))
    @test fallback_views_response.status == 200
    @test String(fallback_views_response.body) == "<p>fallback</p>"
    @test Inochi.resolve_views_root(Context(App(), HTTP.Request("GET", "/"))) == joinpath(Inochi.executable_root(), "views")

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

            default_views_response = Inochi.dispatch(default_views_app, HTTP.Request("GET", "/default-views"))
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

        response = Inochi.dispatch(file_renderer_app, HTTP.Request("GET", "/file-renderer"))
        @test response.status == 200
        @test String(response.body) == "<p>cached</p>"
    end
end

@testset "Request Parsers" begin
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

    response1 = Inochi.dispatch(app, HTTP.Request("POST", "/text", ["Content-Type" => "text/plain; charset=utf-8"], "hello"))
    @test response1.status == 200
    @test String(response1.body) == "hello"

    response2 = Inochi.dispatch(app, HTTP.Request("POST", "/json", ["Content-Type" => "application/json"], "{\"name\":\"alice\",\"count\":3}"))
    @test response2.status == 200
    @test String(response2.body) == "alice:3"

    response3 = Inochi.dispatch(app, HTTP.Request("POST", "/form", ["Content-Type" => "application/x-www-form-urlencoded"], "x=10&y=hello"))
    @test response3.status == 200
    @test String(response3.body) == "10:hello"

    response4 = Inochi.dispatch(app, HTTP.Request("GET", "/query?page=2&q=inochi"))
    @test response4.status == 200
    @test String(response4.body) == "2:inochi"

    parser_app = App()

    bad_text_ctx = Context(parser_app, HTTP.Request("POST", "/text", ["Content-Type" => "application/json"], "\"hello\""))
    @test_throws ArgumentError reqtext(bad_text_ctx)
    @test_throws Exception bad_text_ctx.reqtext

    bad_json_ctx = Context(parser_app, HTTP.Request("POST", "/json", ["Content-Type" => "text/plain"], "{\"name\":\"alice\"}"))
    @test_throws ArgumentError reqjson(bad_json_ctx)
    @test_throws Exception bad_json_ctx.reqjson

    bad_form_ctx = Context(parser_app, HTTP.Request("POST", "/form", ["Content-Type" => "application/json"], "x=10"))
    @test_throws ArgumentError reqform(bad_form_ctx)

    charset_json_ctx = Context(parser_app, HTTP.Request("POST", "/json", ["Content-Type" => "application/json; charset=utf-8"], "{\"name\":\"bob\",\"count\":4}"))
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
    multipart_req = HTTP.Request(
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

    bad_multipart_ctx = Context(parser_app, HTTP.Request("POST", "/upload", ["Content-Type" => "application/json"], "{}"))
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

    req = HTTP.Request("GET", "/cookie", ["Cookie" => "session=abc; theme=dark"])
    response = Inochi.dispatch(app, req)
    @test response.status == 200
    @test String(response.body) == "abc:dark"
    @test HTTP.header(response, "Vary") == "Origin, Cookie"

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/set-cookie"))
    set_cookie_headers = String.(HTTP.headers(response2, "Set-Cookie"))
    @test response2.status == 200
    @test String(response2.body) == "ok"
    @test HTTP.header(response2, "Vary") == "Origin"
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

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/secure-set"))
    cookie_header = only(String.(HTTP.headers(response1, "Set-Cookie")))
    secure_value = first(split(cookie_header, ';'; limit = 2))
    @test occursin("session=", secure_value)

    req = HTTP.Request("GET", "/secure-read", ["Cookie" => secure_value])
    response2 = Inochi.dispatch(app, req)
    @test String(response2.body) == "abc123"
    @test HTTP.header(response2, "Vary") == "Origin, Cookie"

    tampered = secure_value[1:end-1] * (secure_value[end] == '0' ? "1" : "0")
    bad_req = HTTP.Request("GET", "/secure-read", ["Cookie" => tampered])
    response3 = Inochi.dispatch(app, bad_req)
    @test String(response3.body) == "missing"
    @test HTTP.header(response3, "Vary") == "Origin, Cookie"

    invalid_payload = "a"
    invalid_signature = Inochi.secure_cookie_signature(app.config["secret"], invalid_payload)
    invalid_cookie = "session=$(invalid_payload).$(invalid_signature)"
    invalid_req = HTTP.Request("GET", "/secure-read", ["Cookie" => invalid_cookie])
    response4 = Inochi.dispatch(app, invalid_req)
    @test response4.status == 500
    @test String(response4.body) == "Internal Server Error"

    app_without_config_secret = App()

    get(app_without_config_secret, "/secure-read") do ctx
        text(ctx, string(secure_cookie(ctx, "session"; default = "missing")))
    end

    missing_secret_req = HTTP.Request("GET", "/secure-read", ["Cookie" => "session=YWJj.invalidsig"])
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

    explicit_set_response = Inochi.dispatch(app_without_config_secret, HTTP.Request("GET", "/secure-explicit-set"))
    explicit_cookie_header = only(String.(HTTP.headers(explicit_set_response, "Set-Cookie")))
    explicit_value = first(split(explicit_cookie_header, ';'; limit = 2))
    explicit_read_response = Inochi.dispatch(
        app_without_config_secret,
        HTTP.Request("GET", "/secure-explicit-read", ["Cookie" => explicit_value]),
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
        HTTP.Request("POST", "/json", ["Content-Type" => "application/json"], "{\"hello\":1}"),
    )
    @test response.status == 500
    @test String(response.body) == "Internal Server Error"
end
