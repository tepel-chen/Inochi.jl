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

"""
    on_error(app) do ctx, err
        ...
    end

Register an application-wide error handler. The handler receives `ctx` and `err`.
"""
function on_error(handler::Function, app::App)::App
    app.error_handler = handler
    return app
end

function on_error(app::App, handler::Function)::App
    return on_error(handler, app)
end

"""
    on_notfound(app) do ctx
        ...
    end

Register an application-wide 404 handler. The handler receives `ctx`.
"""
function on_notfound(handler::Function, app::App)::App
    app.notfound_handler = handler
    return app
end

function on_notfound(app::App, handler::Function)::App
    return on_notfound(handler, app)
end

function register_route!(app::App, method::AbstractString, path::AbstractString, handler::Function; force_middleware::Bool = false)::App
    normalized_method = uppercase(String(method))
    normalized_path = normalize_path(path)
    is_middleware = force_middleware

    for expanded_path in expand_optional_paths(normalized_path)
        push!(app.routes, RouteDefinition(normalized_method, expanded_path, handler, is_middleware))
    end

    app.dirty = true
    return app
end

"""
    route(app, prefix, subapp)

Mount `subapp` under `prefix` by copying its routes into `app` with the given prefix.
"""
function route(app::App, prefix::AbstractString, subapp::App)::App
    normalized_prefix = normalize_path(prefix)

    for route_def in subapp.routes
        mounted_path = mount_path(normalized_prefix, route_def.path)
        push!(
            app.routes,
            RouteDefinition(route_def.method, mounted_path, route_def.handler, route_def.is_middleware),
        )
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
    return register_route!(app, "ALL", "/*", handler; force_middleware = true)
end

function use(app::App, handler::Function)::App
    return use(handler, app)
end

function use(handler::Function, app::App, path::AbstractString)::App
    return register_route!(app, "ALL", path, handler; force_middleware = true)
end

function use(app::App, path::AbstractString, handler::Function)::App
    return use(handler, app, path)
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

function get(app::App, path::AbstractString, handler::Function)::App
    return get(handler, app, path)
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

function post(app::App, path::AbstractString, handler::Function)::App
    return post(handler, app, path)
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

function put(app::App, path::AbstractString, handler::Function)::App
    return put(handler, app, path)
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

function patch(app::App, path::AbstractString, handler::Function)::App
    return patch(handler, app, path)
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

function delete(app::App, path::AbstractString, handler::Function)::App
    return delete(handler, app, path)
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

function options(app::App, path::AbstractString, handler::Function)::App
    return options(handler, app, path)
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

function head(app::App, path::AbstractString, handler::Function)::App
    return head(handler, app, path)
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

function connect(app::App, path::AbstractString, handler::Function)::App
    return connect(handler, app, path)
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

function trace(app::App, path::AbstractString, handler::Function)::App
    return trace(handler, app, path)
end

function normalize_path(path::AbstractString)::String
    value = String(path)
    isempty(value) && return "/"
    startswith(value, "/") || (value = "/" * value)
    return value
end

function mount_path(prefix::String, path::String)::String
    normalized_path = normalize_path(path)

    if prefix == "/"
        return normalized_path
    elseif normalized_path == "/"
        return prefix
    elseif normalized_path == "/*"
        return prefix * "/*"
    else
        return prefix * normalized_path
    end
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
    ctx = Context(app, req; params = base_params)
    middleware_stack = collect_middlewares(app, req.method, path, final_match)

    try
        function final_handler()
            final_match === nothing && return handle_notfound(app, ctx)
            ctx.params = final_match.params
            return to_response(final_match.handler(ctx), ctx)
        end

        return run_middlewares(middleware_stack, ctx, final_handler)
    catch err
        ctx.backtrace = catch_backtrace()
        return handle_error(app, ctx, err)
    end
end

function get_matcher(app::App, method::AbstractString)::MethodMatcher
    app.dirty && compile_routes!(app)
    return get(app.matchers, uppercase(String(method)), EMPTY_METHOD_MATCHER)
end

const EMPTY_METHOD_MATCHER = MethodMatcher(nothing, Dict{Int,DynamicRoute}(), Dict{String,StaticRoute}())

function match_final_route(matcher::MethodMatcher, path::String)
    static_route = get(matcher.static_map, path, nothing)
    if static_route !== nothing
        return (; handler = static_route.handler, path = static_route.path, params = RouteParams())
    end

    matcher.regex === nothing && return nothing
    matched = match(matcher.regex, path)
    matched === nothing && return nothing

    route_index = matched_route_index(matched)
    route_index === nothing && return nothing

    route = matcher.route_lookup[route_index]
    params = extract_params(matched, route)
    return (; handler = route.handler, path = route.path, params = params)
end

function compile_routes!(app::App)::App
    grouped_routes = Dict{String,Vector{RouteDefinition}}()
    for route in app.routes
        if route.method == "ALL"
            for method in SUPPORTED_HTTP_METHODS
                push!(
                    get!(grouped_routes, method, RouteDefinition[]),
                    RouteDefinition(method, route.path, route.handler, route.is_middleware),
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

    for route in routes
        route.is_middleware && continue

        parsed = parse_route_pattern(route.path)
        if parsed.static
            static_map[route.path] = StaticRoute(route.handler, route.path, route.is_middleware)
            continue
        end

        sentinel_index = capture_index + 1
        capture_index += 1

        param_capture_indexes = Int[]
        for _ in parsed.param_names
            capture_index += 1
            push!(param_capture_indexes, capture_index)
        end

        route_lookup[sentinel_index] = DynamicRoute(route.handler, route.path, parsed.param_names, param_capture_indexes, route.is_middleware)
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
    @assert false "internal route matcher inconsistency"
end

function extract_params(matched::RegexMatch, route::DynamicRoute)::RouteParams
    params = RouteParams()
    for (name, capture_index) in zip(route.param_names, route.param_capture_indexes)
        capture = matched.captures[capture_index]
        params[name] = capture === nothing ? "" : capture
    end
    return params
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
    original_next = ctx.next_handler
    ctx.params = middleware.params
    ctx.next_handler = next_handler
    try
        return to_response(middleware.handler(ctx), ctx)
    finally
        ctx.next_handler = original_next
        ctx.params = original_params
    end
end

function handle_error(app::App, ctx::Context, err)::HTTP.Response
    if app.error_handler === nothing
        return default_error_response()
    end

    result = nothing
    try
        result = app.error_handler(ctx, err)
    catch
        return default_error_response()
    end

    if result === nothing
        return default_error_response()
    end

    return to_response(result, ctx)
end

function handle_notfound(app::App, ctx::Context)::HTTP.Response
    if app.notfound_handler === nothing
        return default_notfound_response()
    end

    result = nothing
    try
        result = app.notfound_handler(ctx)
    catch
        return default_notfound_response()
    end

    if result === nothing
        return default_notfound_response()
    end

    return to_response(result, ctx)
end

default_error_response() = apply_default_headers(HTTP.Response(500, "Internal Server Error"))
default_notfound_response() = apply_default_headers(HTTP.Response(404, "Not Found"))

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
    pattern = route.path
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
        return apply_default_headers(result)
    elseif result isa AbstractString
        return apply_default_headers(HTTP.Response(200, String(result)))
    elseif result isa Vector{UInt8}
        return apply_default_headers(HTTP.Response(200, result))
    end
    throw(ArgumentError("Unsupported response body type: $(typeof(result))"))
end

function to_response(result, ctx::Context)::HTTP.Response
    if result isa Context
        return to_response(result)
    end
    return apply_default_headers(to_response(result), ctx)
end
