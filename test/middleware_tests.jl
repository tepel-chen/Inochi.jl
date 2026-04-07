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
