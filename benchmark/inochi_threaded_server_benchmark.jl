using HTTP
using Inochi
using Sockets

const HANDLER_DELAY = 0.05
const REQUEST_COUNT = 8
const REPEATS = 3

function do_request(port::Integer)
    HTTP.get("http://127.0.0.1:$port/"; headers = ["Connection" => "close"])
end

function run_burst(max_threads::Integer)
    listener = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    _, port = Sockets.getsockname(listener)
    task = @async Inochi.serve(req -> begin
        sleep(HANDLER_DELAY)
        Response(200, Headers(["Content-Type" => "text/plain"]), "ok")
    end, listener; allow_http1 = true, allow_http2 = false, max_threads = max_threads)
    sleep(0.1)
    try
        clients = [@async do_request(port) for _ in 1:REQUEST_COUNT]
        for client in clients
            response = fetch(client)
            response.status == 200 || error("unexpected status $(response.status)")
        end
    finally
        close(listener)
        fetch(task)
    end
end

function benchmark_case(max_threads::Integer)
    run_burst(max_threads)
    samples = Float64[]
    for _ in 1:REPEATS
        start = time_ns()
        run_burst(max_threads)
        push!(samples, (time_ns() - start) / 1e6)
    end
    sort!(samples)
    return samples[cld(length(samples), 2)]
end

function main()
    println("case        max_threads  requests  delay_ms  wall_ms")
    println("----------  -----------  --------  --------  -------")
    for max_threads in (1, 2, 4)
        elapsed_ms = benchmark_case(max_threads)
        println(
            rpad("server", 10),
            "  ",
            lpad(string(max_threads), 11),
            "  ",
            lpad(string(REQUEST_COUNT), 8),
            "  ",
            lpad(string(round(HANDLER_DELAY * 1000, digits = 1)), 8),
            "  ",
            lpad(string(round(elapsed_ms, digits = 1)), 7),
        )
    end
end

main()
