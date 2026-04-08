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

@testset "AST Router" begin
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
    @test haskey(matcher.static_map, "/users/me")
    @test Inochi.match_final_route(matcher, "/users/42").params["id"] == "42"
    @test Inochi.match_final_route(matcher, "/users/42/comments/7").params["comment_id"] == "7"
    @test Inochi.match_final_route(matcher, "/static/css/app.css").params["*"] == "css/app.css"
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
