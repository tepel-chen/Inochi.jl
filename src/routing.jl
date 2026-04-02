const SUPPORTED_HTTP_METHODS = (
    "GET",
    "POST",
    "PUT",
    "PATCH",
    "DELETE",
    "OPTIONS",
    "HEAD",
    "CONNECT",
    "TRACE",
)

function register_route!(app::App, method::AbstractString, path::AbstractString, handler::Function; middleware_scope::Symbol = :exact, force_middleware::Bool = false)::App
    normalized_method = uppercase(String(method))
    normalized_path = normalize_path(path)
    prefers_params = occursin(':', normalized_path)
    is_middleware = force_middleware || handler_supports_next(handler)

    for expanded_path in expand_optional_paths(normalized_path)
        push!(app.routes, RouteDefinition(normalized_method, expanded_path, handler, prefers_params, is_middleware, middleware_scope))
    end

    app.dirty = true
    return app
end

"""
    use(app) do ctx, next
        ...
    end

    use(app, "/prefix") do ctx, next
        ...
    end

Register middleware for all methods. Without a path it applies globally; with a path it applies to the prefix and its descendants.
"""
function use(handler::Function, app::App)::App
    return register_route!(app, "ALL", "/*", handler; middleware_scope = :prefix, force_middleware = true)
end

function use(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "ALL", path, handler; middleware_scope = :prefix, force_middleware = true)
end

"""
    get(app, path) do ...
        ...
    end

Register a `GET` route.
"""
function get(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "GET", path, handler)
end

"""
    post(app, path) do ...
        ...
    end

Register a `POST` route.
"""
function post(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "POST", path, handler)
end

"""
    put(app, path) do ...
        ...
    end

Register a `PUT` route.
"""
function put(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "PUT", path, handler)
end

"""
    patch(app, path) do ...
        ...
    end

Register a `PATCH` route.
"""
function patch(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "PATCH", path, handler)
end

"""
    delete(app, path) do ...
        ...
    end

Register a `DELETE` route.
"""
function delete(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "DELETE", path, handler)
end

"""
    options(app, path) do ...
        ...
    end

Register an `OPTIONS` route.
"""
function options(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "OPTIONS", path, handler)
end

"""
    head(app, path) do ...
        ...
    end

Register a `HEAD` route.
"""
function head(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "HEAD", path, handler)
end

"""
    connect(app, path) do ...
        ...
    end

Register a `CONNECT` route.
"""
function connect(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "CONNECT", path, handler)
end

"""
    trace(app, path) do ...
        ...
    end

Register a `TRACE` route.
"""
function trace(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "TRACE", path, handler)
end

function normalize_path(path::AbstractString)::String
    value = String(path)
    isempty(value) && return "/"
    startswith(value, "/") || (value = "/" * value)
    return value
end

function expand_optional_paths(path::AbstractString)::Vector{String}
    normalized_path = normalize_path(path)
    parts = split(normalized_path, '/', keepempty = false)

    if isempty(parts)
        return ["/"]
    end

    optional_suffix_start = length(parts) + 1
    for index in length(parts):-1:1
        if endswith(parts[index], "?")
            optional_suffix_start = index
        else
            break
        end
    end

    prefix = [String(part) for part in parts[1:optional_suffix_start-1]]
    optional_parts = [String(part) for part in parts[optional_suffix_start:end]]
    expanded = String[]

    for include_count in 0:length(optional_parts)
        combined = copy(prefix)
        for part in optional_parts[1:include_count]
            push!(combined, part[1:end-1])
        end
        push!(expanded, isempty(combined) ? "/" : "/" * join(combined, "/"))
    end

    return expanded
end

function dispatch(app::App, req::HTTP.Request)::HTTP.Response
    path = normalize_path(String(HTTP.URIs.URI(req.target).path))
    matcher = get_matcher(app, req.method)
    final_match = match_final_route(matcher, path)
    base_params = final_match === nothing ? RouteParams() : final_match.params
    ctx = Context(req; params = base_params)
    middleware_stack = collect_middlewares(app, req.method, path, final_match)

    function final_handler()
        final_match === nothing && return HTTP.Response(404, "Not Found")
        if final_match.is_middleware
            not_found = () -> HTTP.Response(404, "Not Found")
            ctx.params = final_match.params
            return to_response(invoke_middleware(final_match.handler, ctx, not_found))
        end
        ctx.params = final_match.params
        return to_response(invoke_handler(final_match.handler, ctx; prefer_params = final_match.prefers_params))
    end

    return run_middlewares(middleware_stack, ctx, final_handler)
end

function get_matcher(app::App, method::AbstractString)::MethodMatcher
    app.dirty && compile_routes!(app)
    return get(app.matchers, uppercase(String(method)), EMPTY_METHOD_MATCHER)
end

const EMPTY_METHOD_MATCHER = MethodMatcher(nothing, Dict{Int,DynamicRoute}(), Dict{String,StaticRoute}())

function match_final_route(matcher::MethodMatcher, path::String)
    static_route = get(matcher.static_map, path, nothing)
    if static_route !== nothing
        return (; handler = static_route.handler, path = static_route.path, params = RouteParams(), prefers_params = static_route.prefers_params, is_middleware = static_route.is_middleware, middleware_scope = static_route.middleware_scope)
    end

    matcher.regex === nothing && return nothing
    matched = match(matcher.regex, path)
    matched === nothing && return nothing

    route_index = matched_route_index(matched)
    route_index === nothing && return nothing

    route = matcher.route_lookup[route_index]
    params = extract_params(matched, route)
    return (; handler = route.handler, path = route.path, params = params, prefers_params = true, is_middleware = route.is_middleware, middleware_scope = route.middleware_scope)
end

function compile_routes!(app::App)::App
    grouped_routes = Dict{String,Vector{RouteDefinition}}()
    for route in app.routes
        if route.method == "ALL"
            for method in SUPPORTED_HTTP_METHODS
                push!(
                    get!(grouped_routes, method, RouteDefinition[]),
                    RouteDefinition(method, route.path, route.handler, route.prefers_params, route.is_middleware, route.middleware_scope),
                )
            end
        else
            push!(get!(grouped_routes, route.method, RouteDefinition[]), route)
        end
    end

    empty!(app.matchers)
    for (method, routes) in grouped_routes
        app.matchers[method] = build_method_matcher(routes)
    end

    app.dirty = false
    return app
end

function build_method_matcher(routes::Vector{RouteDefinition})::MethodMatcher
    static_map = Dict{String,StaticRoute}()
    route_lookup = Dict{Int,DynamicRoute}()
    dynamic_patterns = String[]
    capture_index = 0
    route_index = 0

    for route in routes
        parsed = parse_route_pattern(route.path)
        if parsed.static
            static_map[route.path] = StaticRoute(route.handler, route.path, route.prefers_params, route.is_middleware, route.middleware_scope)
            continue
        end

        route_index += 1
        sentinel_index = capture_index + 1
        capture_index += 1

        param_capture_indexes = Int[]
        for _ in parsed.param_names
            capture_index += 1
            push!(param_capture_indexes, capture_index)
        end

        route_lookup[sentinel_index] = DynamicRoute(route.handler, route.path, parsed.param_names, param_capture_indexes, route.is_middleware, route.middleware_scope)
        push!(dynamic_patterns, "(?:" * "()" * parsed.pattern * ")")
    end

    regex = isempty(dynamic_patterns) ? nothing : Regex("^(?:" * join(dynamic_patterns, "|") * ")\$")
    return MethodMatcher(regex, route_lookup, static_map)
end

function parse_route_pattern(path::String)
    parts = split(path, '/', keepempty = false)
    if isempty(parts)
        return (static = true, pattern = "/", param_names = String[])
    end

    regex_parts = String[]
    param_names = String[]
    is_static = true

    for part in parts
        if startswith(part, ":")
            is_static = false
            push!(param_names, part[2:end])
            push!(regex_parts, "([^/]+)")
        elseif part == "*"
            is_static = false
            push!(param_names, "*")
            push!(regex_parts, "(.*)")
        else
            push!(regex_parts, escape_regex_literal(part))
        end
    end

    return (
        static = is_static,
        pattern = "/" * join(regex_parts, "/"),
        param_names = param_names,
    )
end

function escape_regex_literal(value::AbstractString)::String
    escaped = replace(String(value), r"([.^$|()\[\]{}*+?\\-])" => s"\\\1")
    return escaped
end

function matched_route_index(matched::RegexMatch)
    for (index, capture) in enumerate(matched.captures)
        capture isa AbstractString && isempty(capture) && return index
    end
    return nothing
end

function extract_params(matched::RegexMatch, route::DynamicRoute)::RouteParams
    params = RouteParams()
    for (name, capture_index) in zip(route.param_names, route.param_capture_indexes)
        capture = matched.captures[capture_index]
        params[name] = capture === nothing ? "" : capture
    end
    return params
end

function invoke_handler(handler::Function, ctx::Context; prefer_params::Bool = false)
    try
        return handler(ctx)
    catch err
        if !(err isa MethodError && err.f === handler)
            rethrow(err)
        end
    end

    req = ctx.req
    params = ctx.params

    try
        return handler(req, params)
    catch err
        if !(err isa MethodError && err.f === handler)
            rethrow(err)
        end
    end

    if prefer_params
        try
            return handler(params)
        catch err
            if !(err isa MethodError && err.f === handler)
                rethrow(err)
            end
        end

        try
            return handler(req)
        catch err
            if !(err isa MethodError && err.f === handler)
                rethrow(err)
            end
        end
    else
        try
            return handler(req)
        catch err
            if !(err isa MethodError && err.f === handler)
                rethrow(err)
            end
        end

        if !isempty(params)
            try
                return handler(params)
            catch err
                if !(err isa MethodError && err.f === handler)
                    rethrow(err)
                end
            end
        end
    end

    result = handler()
    if result === nothing
        return ctx
    end
    return result
end

function invoke_middleware(handler::Function, ctx::Context, next::Function)
    try
        return handler(ctx, next)
    catch err
        if !(err isa MethodError && err.f === handler)
            rethrow(err)
        end
    end

    req = ctx.req
    params = ctx.params

    try
        return handler(req, params, next)
    catch err
        if !(err isa MethodError && err.f === handler)
            rethrow(err)
        end
    end

    try
        return handler(req, next)
    catch err
        if !(err isa MethodError && err.f === handler)
            rethrow(err)
        end
    end

    try
        return handler(params, next)
    catch err
        if !(err isa MethodError && err.f === handler)
            rethrow(err)
        end
    end

    return invoke_handler(handler, ctx; prefer_params = true)
end

function handler_supports_next(handler::Function)::Bool
    for method in methods(handler)
        method.nargs >= 4 && return true
    end
    return false
end

function run_middlewares(middlewares, ctx::Context, final_handler::Function, index::Int = 1)::HTTP.Response
    if index > length(middlewares)
        return final_handler()
    end

    middleware = middlewares[index]
    next_called = Ref(false)
    function next_handler()
        next_called[] && throw(ArgumentError("next() may only be called once per middleware"))
        next_called[] = true
        return run_middlewares(middlewares, ctx, final_handler, index + 1)
    end
    original_params = ctx.params
    ctx.params = middleware.params
    result = to_response(invoke_middleware(middleware.handler, ctx, next_handler))
    ctx.params = original_params
    return result
end

function collect_middlewares(app::App, method::AbstractString, path::String, final_match)
    middlewares = NamedTuple[]
    final_path = final_match === nothing ? nothing : final_match.path

    for route in app.routes
        method_matches(route.method, method) || continue
        route.is_middleware || continue
        route.path == final_path && continue

        params = match_middleware_path(route, path)
        params === nothing && continue

        push!(middlewares, (; handler = route.handler, params = params, path = route.path))
    end

    return middlewares
end

method_matches(route_method::String, request_method::AbstractString) = route_method == "ALL" || route_method == uppercase(String(request_method))

is_prefix_wildcard_route(path::String) = endswith(path, "/*")

function match_middleware_path(route::RouteDefinition, path::String)
    if route.middleware_scope == :prefix
        return match_prefix_scope(route.path, path)
    elseif is_prefix_wildcard_route(route.path)
        return match_prefix_wildcard(route.path, path)
    else
        return nothing
    end
end

function match_prefix_scope(pattern::String, path::String)
    if pattern == "/" || pattern == "/*"
        return RouteParams("*" => startswith(path, "/") ? path[2:end] : path)
    elseif is_prefix_wildcard_route(pattern)
        return match_prefix_wildcard(pattern, path)
    elseif path == pattern
        return RouteParams("*" => "")
    else
        prefix = pattern * "/"
        return startswith(path, prefix) ? RouteParams("*" => path[length(prefix)+1:end]) : nothing
    end
end

function match_prefix_wildcard(pattern::String, path::String)
    pattern == "/*" && return RouteParams("*" => startswith(path, "/") ? path[2:end] : path)

    prefix = pattern[1:end-1]
    root = prefix[1:end-1]

    if path == root
        return RouteParams("*" => "")
    elseif startswith(path, prefix)
        return RouteParams("*" => path[length(prefix)+1:end])
    else
        return nothing
    end
end

function to_response(result)::HTTP.Response
    if result isa HTTP.Response
        return result
    elseif result isa AbstractString
        return HTTP.Response(200, String(result))
    elseif result isa Vector{UInt8}
        return HTTP.Response(200, result)
    else
        return HTTP.Response(200, string(result))
    end
end
