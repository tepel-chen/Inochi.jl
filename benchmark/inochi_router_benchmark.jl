using BenchmarkTools
using HTTP
using Inochi

const TEXT_RESPONSE = "Hello, World!"

const ROUTE_CASES = [
    ("short static", "GET", "/user"),
    ("static with same radix", "GET", "/user/comments"),
    ("dynamic route", "GET", "/user/lookup/username/hey"),
    ("mixed static dynamic", "GET", "/event/abcd1234/comments"),
    ("post", "POST", "/event/abcd1234/comment"),
    ("long static", "GET", "/very/deeply/nested/route/hello/there"),
    ("wildcard", "GET", "/static/index.html"),
]

function register_benchmark_routes!()
    app = App()

    get(app, "/static/*") do ctx
        TEXT_RESPONSE
    end

    get(app, "/user") do ctx
        TEXT_RESPONSE
    end

    get(app, "/user/comments") do ctx
        TEXT_RESPONSE
    end

    get(app, "/user/avatar") do ctx
        TEXT_RESPONSE
    end

    get(app, "/user/lookup/username/:username") do ctx
        TEXT_RESPONSE
    end

    get(app, "/user/lookup/email/:address") do ctx
        TEXT_RESPONSE
    end

    get(app, "/event/:id") do ctx
        TEXT_RESPONSE
    end

    get(app, "/event/:id/comments") do ctx
        TEXT_RESPONSE
    end

    post(app, "/event/:id/comment") do ctx
        TEXT_RESPONSE
    end

    get(app, "/map/:location/events") do ctx
        TEXT_RESPONSE
    end

    get(app, "/status") do ctx
        TEXT_RESPONSE
    end

    get(app, "/very/deeply/nested/route/hello/there") do ctx
        TEXT_RESPONSE
    end

    Inochi.compile_routes!(app)
    return app
end

const APP = register_benchmark_routes!()

function match_mode(method::String, path::String)
    matcher = Inochi.get_matcher(APP, method)
    haskey(matcher.static_map, path) && return "map"
    return "regex"
end

function run_match(method::String, path::String)
    matcher = Inochi.get_matcher(APP, method)

    static_handler = get(matcher.static_map, path, nothing)
    if static_handler !== nothing
        return static_handler
    end

    matcher.regex === nothing && error("No route matched $method $path")
    matched = match(matcher.regex, path)
    matched === nothing && error("No route matched $method $path")

    route_index = Inochi.matched_route_index(matched)
    route = matcher.route_lookup[route_index]
    Inochi.extract_params(matched, route)
    return route
end

function benchmark_case(method::String, path::String)
    benchmark = @benchmarkable run_match($method, $path)
    tune!(benchmark)
    run(benchmark)
end

function format_trial_ns(trial::BenchmarkTools.Trial)
    return BenchmarkTools.median(trial).time
end

function format_trial_mem(trial::BenchmarkTools.Trial)
    return BenchmarkTools.median(trial).memory
end

function main()
    println("case                    method  mode   ns/iter  allocs  bytes  path")
    println("----------------------  ------  -----  -------  ------  -----  -------------------------------------")

    for (name, method, path) in ROUTE_CASES
        trial = benchmark_case(method, path)
        mode = match_mode(method, path)
        ns_per_iter = round(Int, format_trial_ns(trial))
        bytes = format_trial_mem(trial)
        allocs = BenchmarkTools.median(trial).allocs

        println(
            rpad(name, 22),
            "  ",
            rpad(method, 6),
            "  ",
            rpad(mode, 5),
            "  ",
            lpad(string(ns_per_iter), 7),
            "  ",
            lpad(string(allocs), 6),
            "  ",
            lpad(string(bytes), 5),
            "  ",
            path,
        )
    end
end

main()
