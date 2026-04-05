using Inochi
using Test
using HTTP
using Base64

const EXPECTED_SERVER_HEADER = "Inochi/" * Inochi.INOCHI_VERSION * " Julia/" * Inochi.JULIA_VERSION
const HTTP_DATE_PATTERN = r"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4} \d{2}:\d{2}:\d{2} GMT$"

@testset "Inochi.jl" begin
    app = App()

    get(app, "/") do ctx
        "hello"
    end

    get(app, "/with-request") do req
        req.method * ":" * String(HTTP.URIs.URI(req.target).path)
    end

    @test length(app.routes) == 2
    @test app.routes[1].method == "GET"
    @test app.routes[1].path == "/"
    @test app.routes[2].path == "/with-request"

    root_response = Inochi.dispatch(app, HTTP.Request("GET", "/"))
    @test root_response.status == 200
    @test String(root_response.body) == "hello"
    @test HTTP.header(root_response, "Server") == EXPECTED_SERVER_HEADER
    @test occursin(HTTP_DATE_PATTERN, HTTP.header(root_response, "Date"))
    @test HTTP.header(root_response, "Vary") == "Origin"

    request_response = Inochi.dispatch(app, HTTP.Request("GET", "/with-request"))
    @test request_response.status == 200
    @test String(request_response.body) == "GET:/with-request"

    missing_response = Inochi.dispatch(app, HTTP.Request("GET", "/missing"))
    @test missing_response.status == 404
    @test String(missing_response.body) == "Not Found"
    @test HTTP.header(missing_response, "Server") == EXPECTED_SERVER_HEADER
    @test occursin(HTTP_DATE_PATTERN, HTTP.header(missing_response, "Date"))
    @test HTTP.header(missing_response, "Vary") == "Origin"
end

@testset "Server Header" begin
    app = App()

    get(app, "/raw") do ctx
        HTTP.Response(201, "created")
    end

    response = Inochi.dispatch(app, HTTP.Request("GET", "/raw"))
    @test response.status == 201
    @test String(response.body) == "created"
    @test HTTP.header(response, "Server") == EXPECTED_SERVER_HEADER
    @test occursin(HTTP_DATE_PATTERN, HTTP.header(response, "Date"))
    @test HTTP.header(response, "Vary") == "Origin"
end

@testset "Regex Router" begin
    app = App()

    get(app, "/users/:id") do params
        params["id"]
    end

    get(app, "/users/:id/comments/:comment_id") do ctx
        string(ctx.params["id"], ":", ctx.params["comment_id"])
    end

    get(app, "/users/me") do ctx
        "me"
    end

    get(app, "/static/*") do params
        params["*"]
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/users/42"))
    @test response1.status == 200
    @test String(response1.body) == "42"

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/users/42/comments/7"))
    @test response2.status == 200
    @test String(response2.body) == "42:7"

    response3 = Inochi.dispatch(app, HTTP.Request("GET", "/users/me"))
    @test response3.status == 200
    @test String(response3.body) == "me"

    response4 = Inochi.dispatch(app, HTTP.Request("GET", "/static/css/app.css"))
    @test response4.status == 200
    @test String(response4.body) == "css/app.css"

    @test app.dirty == false
    matcher = app.matchers["GET"]
    @test matcher.regex !== nothing
    @test haskey(matcher.static_map, "/users/me")
end

@testset "Benchmark Route Set" begin
    app = App()

    get(app, "/user") do ctx
        "ok"
    end

    get(app, "/user/comments") do ctx
        "ok"
    end

    get(app, "/user/avatar") do ctx
        "ok"
    end

    get(app, "/user/lookup/username/:username") do params
        params["username"]
    end

    get(app, "/user/lookup/email/:address") do params
        params["address"]
    end

    get(app, "/event/:id") do params
        params["id"]
    end

    get(app, "/event/:id/comments") do params
        params["id"]
    end

    post(app, "/event/:id/comment") do params
        params["id"]
    end

    get(app, "/map/:location/events") do params
        params["location"]
    end

    get(app, "/status") do ctx
        "ok"
    end

    get(app, "/very/deeply/nested/route/hello/there") do ctx
        "ok"
    end

    get(app, "/static/*") do params
        params["*"]
    end

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/user")).body) == "ok"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/user/comments")).body) == "ok"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/user/avatar")).body) == "ok"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/user/lookup/username/hey")).body) == "hey"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/user/lookup/email/a@b.com")).body) == "a@b.com"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/event/abcd1234")).body) == "abcd1234"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/event/abcd1234/comments")).body) == "abcd1234"
    @test String(Inochi.dispatch(app, HTTP.Request("POST", "/event/abcd1234/comment")).body) == "abcd1234"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/map/tokyo/events")).body) == "tokyo"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/status")).body) == "ok"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/very/deeply/nested/route/hello/there")).body) == "ok"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/static/index.html")).body) == "index.html"
    @test Inochi.dispatch(app, HTTP.Request("GET", "/event/abcd1234/comment")).status == 404
end

@testset "HTTP Methods" begin
    app = App()

    get(app, "/resource") do ctx
        "GET"
    end

    post(app, "/resource") do ctx
        "POST"
    end

    put(app, "/resource") do ctx
        "PUT"
    end

    patch(app, "/resource") do ctx
        "PATCH"
    end

    delete(app, "/resource") do ctx
        "DELETE"
    end

    options(app, "/resource") do ctx
        "OPTIONS"
    end

    head(app, "/resource") do ctx
        "HEAD"
    end

    connect(app, "/resource") do ctx
        "CONNECT"
    end

    trace(app, "/resource") do ctx
        "TRACE"
    end

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/resource")).body) == "GET"
    @test String(Inochi.dispatch(app, HTTP.Request("POST", "/resource")).body) == "POST"
    @test String(Inochi.dispatch(app, HTTP.Request("PUT", "/resource")).body) == "PUT"
    @test String(Inochi.dispatch(app, HTTP.Request("PATCH", "/resource")).body) == "PATCH"
    @test String(Inochi.dispatch(app, HTTP.Request("DELETE", "/resource")).body) == "DELETE"
    @test String(Inochi.dispatch(app, HTTP.Request("OPTIONS", "/resource")).body) == "OPTIONS"
    @test String(Inochi.dispatch(app, HTTP.Request("HEAD", "/resource")).body) == "HEAD"
    @test String(Inochi.dispatch(app, HTTP.Request("CONNECT", "/resource")).body) == "CONNECT"
    @test String(Inochi.dispatch(app, HTTP.Request("TRACE", "/resource")).body) == "TRACE"
end

@testset "App-first Registration" begin
    app = App()

    get(app, "/inline", _ -> "GET")
    post(app, "/inline", _ -> "POST")
    put(app, "/inline", _ -> "PUT")
    patch(app, "/inline", _ -> "PATCH")
    delete(app, "/inline", _ -> "DELETE")
    options(app, "/inline", _ -> "OPTIONS")
    head(app, "/inline", _ -> "HEAD")
    connect(app, "/inline", _ -> "CONNECT")
    trace(app, "/inline", _ -> "TRACE")

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/inline")).body) == "GET"
    @test String(Inochi.dispatch(app, HTTP.Request("POST", "/inline")).body) == "POST"
    @test String(Inochi.dispatch(app, HTTP.Request("PUT", "/inline")).body) == "PUT"
    @test String(Inochi.dispatch(app, HTTP.Request("PATCH", "/inline")).body) == "PATCH"
    @test String(Inochi.dispatch(app, HTTP.Request("DELETE", "/inline")).body) == "DELETE"
    @test String(Inochi.dispatch(app, HTTP.Request("OPTIONS", "/inline")).body) == "OPTIONS"
    @test String(Inochi.dispatch(app, HTTP.Request("HEAD", "/inline")).body) == "HEAD"
    @test String(Inochi.dispatch(app, HTTP.Request("CONNECT", "/inline")).body) == "CONNECT"
    @test String(Inochi.dispatch(app, HTTP.Request("TRACE", "/inline")).body) == "TRACE"
end

@testset "use Method" begin
    app = App()

    use(app, "/shared") do req
        req.method
    end

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/shared")).body) == "GET"
    @test String(Inochi.dispatch(app, HTTP.Request("POST", "/shared")).body) == "POST"
    @test String(Inochi.dispatch(app, HTTP.Request("PUT", "/shared")).body) == "PUT"
    @test String(Inochi.dispatch(app, HTTP.Request("PATCH", "/shared")).body) == "PATCH"
    @test String(Inochi.dispatch(app, HTTP.Request("DELETE", "/shared")).body) == "DELETE"
    @test String(Inochi.dispatch(app, HTTP.Request("OPTIONS", "/shared")).body) == "OPTIONS"
    @test String(Inochi.dispatch(app, HTTP.Request("HEAD", "/shared")).body) == "HEAD"
    @test String(Inochi.dispatch(app, HTTP.Request("CONNECT", "/shared")).body) == "CONNECT"
    @test String(Inochi.dispatch(app, HTTP.Request("TRACE", "/shared")).body) == "TRACE"
end

@testset "Optional Routes" begin
    app = App()

    get(app, "/users/:id?") do params
        get(params, "id", "index")
    end

    get(app, "/files/:dir?/:name?") do params
        string(get(params, "dir", "_"), "/", get(params, "name", "_"))
    end

    get(app, "/status?") do ctx
        "status"
    end

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/users")).body) == "index"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/users/42")).body) == "42"

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/files")).body) == "_/_"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/files/docs")).body) == "docs/_"
    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/files/docs/readme")).body) == "docs/readme"

    @test String(Inochi.dispatch(app, HTTP.Request("GET", "/status")).body) == "status"
    @test Inochi.dispatch(app, HTTP.Request("GET", "/status/extra")).status == 404
end

@testset "Middleware" begin
    app = App()
    events = String[]

    use(app, "/admin/*") do ctx
        push!(events, "auth:" * String(HTTP.URIs.URI(ctx.target).path))
        push!(events, "tail:" * ctx.params["*"])
        next(ctx)
    end

    get(app, "/admin/settings") do ctx
        push!(events, "settings")
        "ok"
    end

    get(app, "/stop/*") do ctx
        "blocked"
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/admin/settings"))
    @test response1.status == 200
    @test String(response1.body) == "ok"
    @test events == ["auth:/admin/settings", "tail:settings", "settings"]

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/stop/secret"))
    @test response2.status == 200
    @test String(response2.body) == "blocked"

    response3 = Inochi.dispatch(app, HTTP.Request("GET", "/admin/missing"))
    @test response3.status == 404
    @test events[end-1:end] == ["auth:/admin/missing", "tail:missing"]
end

@testset "use Middleware" begin
    app = App()
    events = String[]

    use(app) do ctx
        push!(events, "global:" * String(HTTP.URIs.URI(ctx.target).path))
        next(ctx)
    end

    use(app, "/api") do ctx
        push!(events, "api:" * get(ctx.params, "*", ""))
        next(ctx)
    end

    get(app, "/api/users") do ctx
        "users"
    end

    response = Inochi.dispatch(app, HTTP.Request("GET", "/api/users"))
    @test response.status == 200
    @test String(response.body) == "users"
    @test events == ["global:/api/users", "api:users"]

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/other"))
    @test response2.status == 404
    @test events[end] == "global:/other"

    bad_app = App()
    use(bad_app) do ctx
        next(ctx)
        next(ctx)
    end
    get(bad_app, "/boom") do ctx
        "ok"
    end
    response3 = Inochi.dispatch(bad_app, HTTP.Request("GET", "/boom"))
    @test response3.status == 500
    @test String(response3.body) == "Internal Server Error"
end

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

    bad_json_ctx = Context(parser_app, HTTP.Request("POST", "/json", ["Content-Type" => "text/plain"], "{\"name\":\"alice\"}"))
    @test_throws ArgumentError reqjson(bad_json_ctx)

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

@testset "Built-in Middleware" begin
    app = App()
    log_buffer = IOBuffer()

    use(app, cors())
    use(app, etag())
    use(app, logger(; io = log_buffer))
    use(app, "/admin", basicAuth(username = "admin", password = "secret"))

    get(app, "/hello") do ctx
        text(ctx, "hello")
    end

    get(app, "/raw-bytes") do ctx
        UInt8[0x68, 0x69]
    end

    get(app, "/bad-body") do ctx
        123
    end

    get(app, "/bytes") do ctx
        HTTP.Response(200, UInt8[0x68, 0x69])
    end

    get(app, "/byteview") do ctx
        data = UInt8[0x68, 0x69, 0x21]
        HTTP.Response(200, @view data[1:2])
    end

    get(app, "/substring") do ctx
        text = "hello"
        HTTP.Response(200, SubString(text, 1, 2))
    end

    get(app, "/buffer") do ctx
        io = IOBuffer()
        write(io, "buffered")
        HTTP.Response(200, take!(io))
    end

    get(app, "/admin/panel") do ctx
        text(ctx, "ok")
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/hello"))
    @test response1.status == 200
    @test HTTP.header(response1, "Access-Control-Allow-Origin") == "*"
    @test !isempty(HTTP.header(response1, "ETag"))

    etag_cases = (
        ("/hello", "hello"),
        ("/raw-bytes", "hi"),
        ("/bytes", "hi"),
        ("/byteview", "hi"),
        ("/substring", "he"),
        ("/buffer", "buffered"),
    )

    for (path, expected_body) in etag_cases
        response = Inochi.dispatch(app, HTTP.Request("GET", path))
        @test response.status == 200
        @test String(response.body) == expected_body
        @test !isempty(HTTP.header(response, "ETag"))
    end

    response3 = Inochi.dispatch(app, HTTP.Request("GET", "/bad-body"))
    @test response3.status == 500
    @test String(response3.body) == "Internal Server Error"
    @test_throws ArgumentError Inochi.response_bytes(123)

    etag_error_app = App()
    use(etag_error_app, etag())
    get(etag_error_app, "/bad") do ctx
        HTTP.Response(200, 123)
    end
    etag_error_response = Inochi.dispatch(etag_error_app, HTTP.Request("GET", "/bad"))
    @test etag_error_response.status == 500
    @test String(etag_error_response.body) == "Internal Server Error"

    response4 = Inochi.dispatch(app, HTTP.Request("OPTIONS", "/hello"))
    @test response4.status == 204
    @test HTTP.header(response4, "Access-Control-Allow-Methods") == join(Inochi.SUPPORTED_HTTP_METHODS, ", ")

    response5 = Inochi.dispatch(app, HTTP.Request("GET", "/admin/panel"))
    @test response5.status == 401
    @test HTTP.header(response5, "WWW-Authenticate") == "Basic realm=\"Restricted\""

    malformed_auth_response = Inochi.dispatch(app, HTTP.Request("GET", "/admin/panel", ["Authorization" => "Basic !!!"], ""))
    @test malformed_auth_response.status == 401
    @test HTTP.header(malformed_auth_response, "WWW-Authenticate") == "Basic realm=\"Restricted\""

    auth_header = "Basic " * Base64.base64encode("admin:secret")
    response6 = Inochi.dispatch(app, HTTP.Request("GET", "/admin/panel", ["Authorization" => auth_header]))
    @test response6.status == 200
    @test String(response6.body) == "ok"

    response7 = Inochi.dispatch(app, HTTP.Request("GET", "/hello", ["If-None-Match" => HTTP.header(response1, "ETag")]))
    @test response7.status == 304
    @test HTTP.header(response7, "ETag") == HTTP.header(response1, "ETag")

    response7b = Inochi.dispatch(app, HTTP.Request("GET", "/hello", ["If-None-Match" => "\"bogus\""]))
    @test response7b.status == 200
    @test String(response7b.body) == "hello"
    @test !isempty(HTTP.header(response7b, "ETag"))

    logs = String(take!(log_buffer))
    @test occursin("GET /hello -> 200", logs)
    @test occursin("GET /admin/panel -> 200", logs)
end

@testset "CSRF Without Middleware" begin
    app = App()

    get(app, "/token") do ctx
        text(ctx, csrf_token(ctx))
    end

    response = Inochi.dispatch(app, HTTP.Request("GET", "/token"))
    @test response.status == 200
    @test !isempty(String(response.body))
    @test isempty(HTTP.headers(response, "Set-Cookie"))
end

@testset "CSRF Middleware" begin
    app = App()
    use(app, csrf())

    get(app, "/form") do ctx
        text(ctx, csrf_token(ctx))
    end

    post(app, "/submit") do ctx
        text(ctx, "ok")
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/form"))
    @test response1.status == 200
    issued_cookie = only(String.(HTTP.headers(response1, "Set-Cookie")))
    @test occursin("csrf_token=", issued_cookie)
    @test occursin("SameSite=Lax", issued_cookie)
    token = split(split(issued_cookie, ';'; limit = 2)[1], '='; limit = 2)[2]
    @test String(response1.body) == token

    response2 = Inochi.dispatch(app, HTTP.Request("POST", "/submit", ["Cookie" => "csrf_token=" * token], ""))
    @test response2.status == 403

    response3 = Inochi.dispatch(
        app,
        HTTP.Request(
            "POST",
            "/submit",
            ["Cookie" => "csrf_token=" * token, "X-CSRF-Token" => token],
            "",
        ),
    )
    @test response3.status == 200
    @test String(response3.body) == "ok"

    form_body = "csrf_token=" * HTTP.URIs.escapeuri(token)
    response4 = Inochi.dispatch(
        app,
        HTTP.Request(
            "POST",
            "/submit",
            ["Cookie" => "csrf_token=" * token, "Content-Type" => "application/x-www-form-urlencoded"],
            form_body,
        ),
    )
    @test response4.status == 200

    missing_cookie_response = Inochi.dispatch(app, HTTP.Request("GET", "/form"))
    missing_cookie = only(String.(HTTP.headers(missing_cookie_response, "Set-Cookie")))
    @test occursin("csrf_token=", missing_cookie)
    @test String(missing_cookie_response.body) != ""

    invalid_cookie_response = Inochi.dispatch(app, HTTP.Request("GET", "/form", ["Cookie" => "csrf_token=not-base64"], ""))
    @test isempty(HTTP.headers(invalid_cookie_response, "Set-Cookie"))
    @test String(invalid_cookie_response.body) == "not-base64"
end

@testset "CSRF SameSite" begin
    default_mode_app = App()
    use(default_mode_app, csrf(samesite = "default"))
    get(default_mode_app, "/token") do ctx
        text(ctx, csrf_token(ctx))
    end
    default_mode_response = Inochi.dispatch(default_mode_app, HTTP.Request("GET", "/token"))
    default_mode_cookie = only(String.(HTTP.headers(default_mode_response, "Set-Cookie")))
    @test !occursin("SameSite=", default_mode_cookie)

    strict_app = App()
    use(strict_app, csrf(samesite = "Strict"))
    get(strict_app, "/token") do ctx
        text(ctx, csrf_token(ctx))
    end
    strict_response = Inochi.dispatch(strict_app, HTTP.Request("GET", "/token"))
    strict_cookie = only(String.(HTTP.headers(strict_response, "Set-Cookie")))
    @test occursin("SameSite=Strict", strict_cookie)

    none_app = App()
    use(none_app, csrf(samesite = "None"))
    get(none_app, "/token") do ctx
        text(ctx, csrf_token(ctx))
    end
    none_response = Inochi.dispatch(none_app, HTTP.Request("GET", "/token"))
    none_cookie = only(String.(HTTP.headers(none_response, "Set-Cookie")))
    @test occursin("SameSite=None", none_cookie)

    default_app = App()
    use(default_app, csrf(samesite = "Lax"))
    get(default_app, "/token") do ctx
        text(ctx, csrf_token(ctx))
    end
    default_response = Inochi.dispatch(default_app, HTTP.Request("GET", "/token"))
    default_cookie = only(String.(HTTP.headers(default_response, "Set-Cookie")))
    @test occursin("SameSite=Lax", default_cookie)

    none_mode_app = App()
    use(none_mode_app, csrf(samesite = nothing))
    get(none_mode_app, "/token") do ctx
        text(ctx, csrf_token(ctx))
    end
    none_mode_response = Inochi.dispatch(none_mode_app, HTTP.Request("GET", "/token"))
    none_mode_cookie = only(String.(HTTP.headers(none_mode_response, "Set-Cookie")))
    @test !occursin("SameSite=", none_mode_cookie)

    @test_throws ArgumentError csrf(samesite = "Bogus")
end

@testset "Error Handling" begin
    app = App()

    get(app, "/boom") do ctx
        error("boom")
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/boom"))
    @test response1.status == 500
    @test String(response1.body) == "Internal Server Error"

    custom_app = App()

    use(custom_app, "/fail") do ctx
        next(ctx)
    end

    get(custom_app, "/fail") do ctx
        throw(ArgumentError("bad request"))
    end

    on_error(custom_app) do ctx, err
        json(ctx, Dict("error" => string(err)); status = 418)
    end

    response2 = Inochi.dispatch(custom_app, HTTP.Request("GET", "/fail"))
    @test response2.status == 418
    @test HTTP.header(response2, "Content-Type") == "application/json; charset=utf-8"
    @test occursin("bad request", String(response2.body))

    trace_app = App()
    get(trace_app, "/fail") do ctx
        error("boom")
    end
    on_error(trace_app) do ctx, err
        text(ctx, sprint(showerror, err, ctx.backtrace); status = 500)
    end
    trace_response = Inochi.dispatch(trace_app, HTTP.Request("GET", "/fail"))
    @test trace_response.status == 500
    @test occursin("boom", String(trace_response.body))
    @test occursin("Stacktrace", String(trace_response.body))

    default_error_app = App()
    get(default_error_app, "/fail") do ctx
        throw(ArgumentError("bad request"))
    end
    on_error(default_error_app) do ctx, err
        nothing
    end
    default_error_response = Inochi.dispatch(default_error_app, HTTP.Request("GET", "/fail"))
    @test default_error_response.status == 500
    @test String(default_error_response.body) == "Internal Server Error"

    failing_error_app = App()
    get(failing_error_app, "/fail") do ctx
        throw(ArgumentError("bad request"))
    end
    on_error(failing_error_app) do ctx, err
        error("handler boom")
    end
    failing_error_response = Inochi.dispatch(failing_error_app, HTTP.Request("GET", "/fail"))
    @test failing_error_response.status == 500
    @test String(failing_error_response.body) == "Internal Server Error"
end

@testset "Not Found Handling" begin
    app = App()

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/missing"))
    @test response1.status == 404
    @test String(response1.body) == "Not Found"

    custom_app = App()

    on_notfound(custom_app) do ctx
        text(ctx, "missing:" * String(HTTP.URIs.URI(ctx.target).path); status = 404)
    end

    response2 = Inochi.dispatch(custom_app, HTTP.Request("GET", "/nope"))
    @test response2.status == 404
    @test String(response2.body) == "missing:/nope"

    default_notfound_app = App()
    on_notfound(default_notfound_app) do ctx
        nothing
    end
    default_notfound_response = Inochi.dispatch(default_notfound_app, HTTP.Request("GET", "/still-missing"))
    @test default_notfound_response.status == 404
    @test String(default_notfound_response.body) == "Not Found"

    failing_notfound_app = App()
    on_notfound(failing_notfound_app) do ctx
        error("handler boom")
    end
    failing_notfound_response = Inochi.dispatch(failing_notfound_app, HTTP.Request("GET", "/still-missing"))
    @test failing_notfound_response.status == 404
    @test String(failing_notfound_response.body) == "Not Found"
end

@testset "Mounted Apps" begin
    admin = App()
    root = App()
    public = App()
    events = String[]

    use(admin) do ctx
        push!(events, "mw:" * String(HTTP.URIs.URI(ctx.target).path))
        next(ctx)
    end

    get(admin, "/") do ctx
        "admin-root"
    end

    get(admin, "/users/:id") do ctx
        "user:" * ctx.params["id"]
    end

    get(admin, "/reports/:name?") do ctx
        get(ctx.params, "name", "index")
    end

    get(public, "/") do ctx
        "public-root"
    end

    get(public, "/info") do ctx
        "public-info"
    end

    route(root, "/", public)
    route(root, "/admin", admin)

    response0 = Inochi.dispatch(root, HTTP.Request("GET", "/"))
    @test response0.status == 200
    @test String(response0.body) == "public-root"

    response0b = Inochi.dispatch(root, HTTP.Request("GET", "/info"))
    @test response0b.status == 200
    @test String(response0b.body) == "public-info"

    response1 = Inochi.dispatch(root, HTTP.Request("GET", "/admin"))
    @test response1.status == 200
    @test String(response1.body) == "admin-root"

    response2 = Inochi.dispatch(root, HTTP.Request("GET", "/admin/users/42"))
    @test response2.status == 200
    @test String(response2.body) == "user:42"

    response3 = Inochi.dispatch(root, HTTP.Request("GET", "/admin/reports"))
    @test response3.status == 200
    @test String(response3.body) == "index"

    response4 = Inochi.dispatch(root, HTTP.Request("GET", "/admin/reports/daily"))
    @test response4.status == 200
    @test String(response4.body) == "daily"

    @test events == [
        "mw:/admin",
        "mw:/admin/users/42",
        "mw:/admin/reports",
        "mw:/admin/reports/daily",
    ]
end

@testset "Static Files" begin
    mktempdir(@__DIR__) do tmpdir
        assets_dir = joinpath(tmpdir, "assets")
        mkpath(assets_dir)
        html_path = joinpath(assets_dir, "index.html")
        css_path = joinpath(assets_dir, "app.css")
        write(html_path, "<h1>Hello</h1>")
        write(css_path, "body { color: red; }")
        secret_path = joinpath(tmpdir, "secret.txt")
        write(secret_path, "top-secret")

        app = App()
        get(static(assets_dir), app, "/static/*")

        response1 = Inochi.dispatch(app, HTTP.Request("GET", "/static/index.html"))
        @test response1.status == 200
        @test String(response1.body) == "<h1>Hello</h1>"
        @test HTTP.header(response1, "Content-Type") == "text/html; charset=utf-8"
        @test !isempty(HTTP.header(response1, "ETag"))

        response2 = Inochi.dispatch(app, HTTP.Request("GET", "/static/app.css"))
        @test response2.status == 200
        @test HTTP.header(response2, "Content-Type") == "text/css; charset=utf-8"
        @test !isempty(HTTP.header(response2, "ETag"))

        response3 = Inochi.dispatch(app, HTTP.Request("GET", "/static/../secret.txt"))
        @test response3.status == 403

        response4 = Inochi.dispatch(app, HTTP.Request("GET", "/static/index.html", ["If-None-Match" => HTTP.header(response1, "ETag")]))
        @test response4.status == 304
        @test HTTP.header(response4, "ETag") == HTTP.header(response1, "ETag")
    end
end

@testset "sendFile" begin
    fixture_dir = joinpath(@__DIR__, "fixtures")
    mkpath(fixture_dir)
    fixture_path = joinpath(fixture_dir, "sample.txt")
    write(fixture_path, "fixture")

    app = App()

    get(app, "/download") do ctx
        sendFile(ctx, "fixtures/sample.txt")
    end

    get(app, "/blocked") do ctx
        sendFile("../Project.toml")
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/download"))
    @test response1.status == 200
    @test String(response1.body) == "fixture"
    @test HTTP.header(response1, "Content-Type") == "text/plain; charset=utf-8"
    @test !isempty(HTTP.header(response1, "ETag"))

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/blocked"))
    @test response2.status == 403

    response3 = Inochi.dispatch(app, HTTP.Request("GET", "/download", ["If-None-Match" => HTTP.header(response1, "ETag")]))
    @test response3.status == 304
    @test HTTP.header(response3, "ETag") == HTTP.header(response1, "ETag")
end
