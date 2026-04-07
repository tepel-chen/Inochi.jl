@testset "Server" begin
    HTTP.serve!(handler::Function, host::String, port::Integer; kw...) = (:stub, host, port, kw)

    app = App()
    response = Inochi.start(app; host = "127.0.0.1", port = 0)

    @test response[1] == :stub
    @test response[2] == "127.0.0.1"
    @test response[3] == 0
end
