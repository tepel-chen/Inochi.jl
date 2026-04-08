using BenchmarkTools
using HTTP
using Inochi

const TEXT_RESPONSE = "Hello, World!"

const CASES = [
    ("no middleware", "GET", "/ping", "no middleware"),
    ("one global", "GET", "/ping", "one global"),
    ("four global", "GET", "/ping", "four global"),
    ("global + prefix skip", "GET", "/ping", "global + prefix skip"),
    ("global + prefix hit", "GET", "/api/ping", "global + prefix hit"),
    ("nested prefix hit", "GET", "/admin/api/v1/ping", "nested prefix hit"),
]

const CASE_PATHS = Dict(case_name => path for (case_name, _, path, _) in CASES)

function build_app(; globals::Int = 0, prefixes::Vector{String} = String[], route::String = "/ping")
    app = App()

    for _ in 1:globals
        use(app) do ctx
            next(ctx)
        end
    end

    for prefix in prefixes
        use(app, prefix) do ctx
            next(ctx)
        end
    end

    get(app, route) do ctx
        TEXT_RESPONSE
    end

    Inochi.compile_routes!(app)
    return app
end

const APPS = Dict(
    "no middleware" => build_app(),
    "one global" => build_app(globals = 1),
    "four global" => build_app(globals = 4),
    "global + prefix skip" => build_app(globals = 1, prefixes = ["/admin"], route = "/ping"),
    "global + prefix hit" => build_app(globals = 1, prefixes = ["/api"], route = "/api/ping"),
    "nested prefix hit" => build_app(globals = 1, prefixes = ["/admin", "/admin/api", "/admin/api/v1"], route = "/admin/api/v1/ping"),
)

function run_dispatch(case_name::String)
    app = APPS[case_name]
    path = CASE_PATHS[case_name]
    response = Inochi.dispatch(app, HTTP.Request("GET", path))
    response.status == 200 || error("unexpected status $(response.status) for $case_name")
    return response
end

function benchmark_case(case_name::String)
    benchmark = @benchmarkable run_dispatch($case_name)
    tune!(benchmark)
    run(benchmark)
end

function main()
    println("case                 method  path                ns/iter  allocs  bytes")
    println("-------------------  ------  ------------------  -------  ------  -----")

    for (case_name, method, path, _) in CASES
        trial = benchmark_case(case_name)
        ns_per_iter = round(Int, BenchmarkTools.median(trial).time)
        bytes = BenchmarkTools.median(trial).memory
        allocs = BenchmarkTools.median(trial).allocs

        println(
            rpad(case_name, 19),
            "  ",
            rpad(method, 6),
            "  ",
            rpad(path, 18),
            "  ",
            lpad(string(ns_per_iter), 7),
            "  ",
            lpad(string(allocs), 6),
            "  ",
            lpad(string(bytes), 5),
        )
    end
end

main()
