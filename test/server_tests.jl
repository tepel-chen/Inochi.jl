@testset "Server" begin
    InochiCore.serve(handler::Function; host::String = "127.0.0.1", port::Integer = 8080, kw...) = (:stub, host, port, kw)

    app = App()
    response = Inochi.start(app; host = "127.0.0.1", port = 0)

    @test response[1] == :stub
    @test response[2] == "127.0.0.1"
    @test response[3] == 0
    @test haskey(response[4], :max_content_size)
    @test response[4][:max_content_size] == app.config["max_content_size"]
end
