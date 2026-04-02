using Inochi
using Test
using HTTP
using Base64

@testset "Inochi.jl" begin
    app = App()

    get(app, "/") do
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

    request_response = Inochi.dispatch(app, HTTP.Request("GET", "/with-request"))
    @test request_response.status == 200
    @test String(request_response.body) == "GET:/with-request"

    missing_response = Inochi.dispatch(app, HTTP.Request("GET", "/missing"))
    @test missing_response.status == 404
    @test String(missing_response.body) == "Not Found"
end

@testset "Regex Router" begin
    app = App()

    get(app, "/users/:id") do params
        params["id"]
    end

    get(app, "/users/:id/comments/:comment_id") do _, params
        string(params["id"], ":", params["comment_id"])
    end

    get(app, "/users/me") do
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

    get(app, "/user") do
        "ok"
    end

    get(app, "/user/comments") do
        "ok"
    end

    get(app, "/user/avatar") do
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

    get(app, "/status") do
        "ok"
    end

    get(app, "/very/deeply/nested/route/hello/there") do
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

    get(app, "/resource") do
        "GET"
    end

    post(app, "/resource") do
        "POST"
    end

    put(app, "/resource") do
        "PUT"
    end

    patch(app, "/resource") do
        "PATCH"
    end

    delete(app, "/resource") do
        "DELETE"
    end

    options(app, "/resource") do
        "OPTIONS"
    end

    head(app, "/resource") do
        "HEAD"
    end

    connect(app, "/resource") do
        "CONNECT"
    end

    trace(app, "/resource") do
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

    get(app, "/status?") do
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

    get(app, "/admin/*") do req, params, next
        push!(events, "auth:" * String(HTTP.URIs.URI(req.target).path))
        push!(events, "tail:" * params["*"])
        next()
    end

    get(app, "/admin/settings") do
        push!(events, "settings")
        "ok"
    end

    get(app, "/stop/*") do
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

    use(app) do ctx, next
        push!(events, "global:" * String(HTTP.URIs.URI(ctx.target).path))
        next()
    end

    use(app, "/api") do ctx, next
        push!(events, "api:" * get(ctx.params, "*", ""))
        next()
    end

    get(app, "/api/users") do
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
    use(bad_app) do _, next
        next()
        next()
    end
    get(bad_app, "/boom") do
        "ok"
    end
    @test_throws ArgumentError Inochi.dispatch(bad_app, HTTP.Request("GET", "/boom"))
end

@testset "Context" begin
    app = App()

    get(app, "/ctx/:id") do ctx
        set!(ctx, :seen, true)
        text(ctx, "id=" * ctx.params["id"]; status = 201)
    end

    use(app, "/ctx/*") do ctx, next
        header!(ctx, "X-Middleware", "on")
        next()
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

@testset "Request Parsers" begin
    app = App()

    post(app, "/text") do ctx
        text(ctx, ctx.reqtext())
    end

    post(app, "/json") do ctx
        payload = ctx.reqjson()
        text(ctx, string(payload["name"], ":", payload["count"]))
    end

    post(app, "/form") do ctx
        form = ctx.reqform()
        text(ctx, string(form["x"], ":", form["y"]))
    end

    get(app, "/query") do ctx
        query = ctx.reqquery()
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

    bad_text_ctx = Context(HTTP.Request("POST", "/text", ["Content-Type" => "application/json"], "\"hello\""))
    @test_throws ArgumentError reqtext(bad_text_ctx)

    bad_json_ctx = Context(HTTP.Request("POST", "/json", ["Content-Type" => "text/plain"], "{\"name\":\"alice\"}"))
    @test_throws ArgumentError reqjson(bad_json_ctx)

    bad_form_ctx = Context(HTTP.Request("POST", "/form", ["Content-Type" => "application/json"], "x=10"))
    @test_throws ArgumentError reqform(bad_form_ctx)

    charset_json_ctx = Context(HTTP.Request("POST", "/json", ["Content-Type" => "application/json; charset=utf-8"], "{\"name\":\"bob\",\"count\":4}"))
    @test reqjson(charset_json_ctx)["name"] == "bob"
end

@testset "Cookies" begin
    app = App()

    get(app, "/cookie") do ctx
        text(ctx, ctx.cookie("session", "missing") * ":" * ctx.cookie["theme"])
    end

    get(app, "/set-cookie") do ctx
        ctx.setcookie("session", "abc"; path = "/", httponly = true)
        ctx.setcookie("theme", "dark"; maxage = 60)
        text(ctx, "ok")
    end

    req = HTTP.Request("GET", "/cookie", ["Cookie" => "session=abc; theme=dark"])
    response = Inochi.dispatch(app, req)
    @test response.status == 200
    @test String(response.body) == "abc:dark"

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/set-cookie"))
    set_cookie_headers = String.(HTTP.headers(response2, "Set-Cookie"))
    @test response2.status == 200
    @test String(response2.body) == "ok"
    @test length(set_cookie_headers) == 2
    @test any(header -> occursin("session=abc", header), set_cookie_headers)
    @test any(header -> occursin("HttpOnly", header), set_cookie_headers)
    @test any(header -> occursin("theme=dark", header), set_cookie_headers)
    @test any(header -> occursin("Max-Age=60", header), set_cookie_headers)
end

@testset "Secure Cookies" begin
    app = App()

    get(app, "/secure-set") do ctx
        set_secure_cookie(ctx, "session", "abc123"; secret = "top-secret", path = "/", httponly = true)
        text(ctx, "ok")
    end

    get(app, "/secure-read") do ctx
        text(ctx, string(secure_cookie(ctx, "session"; secret = "top-secret", default = "missing")))
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/secure-set"))
    cookie_header = only(String.(HTTP.headers(response1, "Set-Cookie")))
    secure_value = first(split(cookie_header, ';'; limit = 2))
    @test occursin("session=", secure_value)

    req = HTTP.Request("GET", "/secure-read", ["Cookie" => secure_value])
    response2 = Inochi.dispatch(app, req)
    @test String(response2.body) == "abc123"

    tampered = secure_value[1:end-1] * (secure_value[end] == '0' ? "1" : "0")
    bad_req = HTTP.Request("GET", "/secure-read", ["Cookie" => tampered])
    response3 = Inochi.dispatch(app, bad_req)
    @test String(response3.body) == "missing"
end

@testset "Built-in Middleware" begin
    app = App()
    log_buffer = IOBuffer()

    use(app, cors())
    use(app, logger(; io = log_buffer))
    use(app, "/admin", basicAuth(username = "admin", password = "secret"))

    get(app, "/hello") do ctx
        text(ctx, "hello")
    end

    get(app, "/admin/panel") do ctx
        text(ctx, "ok")
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/hello"))
    @test response1.status == 200
    @test HTTP.header(response1, "Access-Control-Allow-Origin") == "*"

    response2 = Inochi.dispatch(app, HTTP.Request("OPTIONS", "/hello"))
    @test response2.status == 204
    @test HTTP.header(response2, "Access-Control-Allow-Methods") == join(Inochi.SUPPORTED_HTTP_METHODS, ", ")

    response3 = Inochi.dispatch(app, HTTP.Request("GET", "/admin/panel"))
    @test response3.status == 401
    @test HTTP.header(response3, "WWW-Authenticate") == "Basic realm=\"Restricted\""

    auth_header = "Basic " * Base64.base64encode("admin:secret")
    response4 = Inochi.dispatch(app, HTTP.Request("GET", "/admin/panel", ["Authorization" => auth_header]))
    @test response4.status == 200
    @test String(response4.body) == "ok"

    logs = String(take!(log_buffer))
    @test occursin("GET /hello -> 200", logs)
    @test occursin("GET /admin/panel -> 200", logs)
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

        response2 = Inochi.dispatch(app, HTTP.Request("GET", "/static/app.css"))
        @test response2.status == 200
        @test HTTP.header(response2, "Content-Type") == "text/css; charset=utf-8"

        response3 = Inochi.dispatch(app, HTTP.Request("GET", "/static/../secret.txt"))
        @test response3.status == 403
    end
end

@testset "sendFile" begin
    fixture_dir = joinpath(@__DIR__, "fixtures")
    mkpath(fixture_dir)
    fixture_path = joinpath(fixture_dir, "sample.txt")
    write(fixture_path, "fixture")

    app = App()

    get(app, "/download") do
        sendFile("fixtures/sample.txt")
    end

    get(app, "/blocked") do
        sendFile("../Project.toml")
    end

    response1 = Inochi.dispatch(app, HTTP.Request("GET", "/download"))
    @test response1.status == 200
    @test String(response1.body) == "fixture"
    @test HTTP.header(response1, "Content-Type") == "text/plain; charset=utf-8"

    response2 = Inochi.dispatch(app, HTTP.Request("GET", "/blocked"))
    @test response2.status == 403
end
