@testset "Static Files" begin
    mktempdir(@__DIR__) do tmpdir
        assets_dir = joinpath(tmpdir, "assets")
        mkpath(assets_dir)
        html_path = joinpath(assets_dir, "index.html")
        css_path = joinpath(assets_dir, "app.css")
        write(html_path, "<h1>Hello</h1>")
        write(css_path, "body { color: red; }")

        app = App()

        get(app, "/assets/*") do ctx
            sendFile(ctx, "assets/" * ctx.params["*"]; root = tmpdir)
        end

        get(app, "/assets-direct/*") do ctx
            sendFile("assets/" * ctx.params["*"]; root = tmpdir)
        end

        get(app, "/assets-root/*") do ctx
            sendFile(ctx, ctx.params["*"]; root = joinpath(tmpdir, "assets"))
        end

        get(app, "/escape") do ctx
            sendFile(ctx, "../secret.txt"; root = tmpdir)
        end

        response1 = Inochi.dispatch(app, InochiCore.Request("GET", "/assets/index.html"))
        @test response1.status == 200
        @test String(response1.body) == "<h1>Hello</h1>"
        @test response1.headers["Content-Type"] == "text/html; charset=utf-8"
        @test !isempty(response1.headers["ETag"])

        response2 = Inochi.dispatch(app, InochiCore.Request("GET", "/assets/app.css"))
        @test response2.status == 200
        @test String(response2.body) == "body { color: red; }"
        @test response2.headers["Content-Type"] == "text/css; charset=utf-8"

        response3 = Inochi.dispatch(app, InochiCore.Request("GET", "/assets/missing.txt"))
        @test response3.status == 404

        response4 = Inochi.dispatch(app, InochiCore.Request("GET", "/escape"))
        @test response4.status == 403

        response5 = Inochi.dispatch(app, InochiCore.Request("GET", "/assets-direct/index.html"))
        @test response5.status == 200

        response6 = Inochi.dispatch(app, InochiCore.Request("GET", "/assets-root/index.html"))
        @test response6.status == 200

        response7 = Inochi.dispatch(app, InochiCore.Request("GET", "/assets/index.html", ["If-None-Match" => response1.headers["ETag"]]))
        @test response7.status == 304
        @test response7.headers["ETag"] == response1.headers["ETag"]
    end

    mktempdir(@__DIR__) do tmpdir
        assets_dir = joinpath(tmpdir, "static-root")
        mkpath(assets_dir)
        write(joinpath(assets_dir, "app.css"), "body { color: blue; }")

        app = App()
        get(static(assets_dir), app, "/assets/*")

        response = Inochi.dispatch(app, InochiCore.Request("GET", "/assets/app.css"))
        @test response.status == 200
        @test String(response.body) == "body { color: blue; }"
        @test response.headers["Content-Type"] == "text/css; charset=utf-8"
    end

    @test Inochi.executable_root() == normpath(isempty(Base.PROGRAM_FILE) ? pwd() : dirname(abspath(Base.PROGRAM_FILE)))
    @test Inochi.content_type_for_path("x.html") == "text/html; charset=utf-8"
    @test Inochi.content_type_for_path("x.css") == "text/css; charset=utf-8"
    @test Inochi.content_type_for_path("x.json") == "application/json; charset=utf-8"
    @test Inochi.content_type_for_path("x.bin") == "application/octet-stream"
    @test Inochi.safe_join("/tmp", "../secret") === nothing
    @test Inochi.safe_join("/tmp", "ok/file.txt") !== nothing
end

@testset "sendFile" begin
    fixture_dir = joinpath(@__DIR__, "fixtures")
    mkpath(fixture_dir)
    fixture_path = joinpath(fixture_dir, "sample.txt")
    write(fixture_path, "fixture")

    app = App()

    get(app, "/download") do ctx
        sendFile(ctx, fixture_path; root = @__DIR__)
    end

    get(app, "/blocked") do ctx
        sendFile(ctx, "../outside.txt"; root = @__DIR__)
    end

    response1 = Inochi.dispatch(app, InochiCore.Request("GET", "/download"))
    @test response1.status == 200
    @test String(response1.body) == "fixture"
    @test response1.headers["Content-Type"] == "text/plain; charset=utf-8"
    @test !isempty(response1.headers["ETag"])

    response2 = Inochi.dispatch(app, InochiCore.Request("GET", "/blocked"))
    @test response2.status == 403
    @test String(response2.body) == "Forbidden"

    response3 = Inochi.dispatch(app, InochiCore.Request("GET", "/download", ["If-None-Match" => response1.headers["ETag"]]))
    @test response3.status == 304
    @test response3.headers["ETag"] == response1.headers["ETag"]
end
