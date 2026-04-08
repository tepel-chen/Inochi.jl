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
    base_params = final_match === nothing ? RouteParams() : matched_params(final_match)
    ctx = Context(app, req; params = base_params)
    middleware_stack = collect_middlewares(app, req.method, path, final_match)

    try
        function final_handler()
            final_match === nothing && return handle_notfound(app, ctx)
            ctx.params = matched_params(final_match)
            return to_response(matched_handler(final_match)(ctx), ctx)
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

@noinline function empty_dynamic_matcher(path::String)
    return nothing
end

const EMPTY_METHOD_MATCHER = MethodMatcher(empty_dynamic_matcher, Dict{String,StaticRoute}())

function match_final_route(matcher::MethodMatcher, path::String)
    static_route = get(matcher.static_map, path, nothing)
    if static_route !== nothing
        return static_route
    end

    return matcher.dynamic_matcher(path)
end

@inline matched_handler(match::StaticRoute) = match.handler
@inline matched_handler(match::MatchedRoute) = match.handler
@inline matched_path(match::StaticRoute) = match.path
@inline matched_path(match::MatchedRoute) = match.path
@inline matched_params(::StaticRoute) = RouteParams()
@inline matched_params(match::MatchedRoute) = match.params

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
    dynamic_routes = DynamicRoute[]

    for route in routes
        route.is_middleware && continue

        parsed = parse_route_pattern(route.path)
        if parsed.static
            static_map[route.path] = StaticRoute(route.handler, route.path, route.is_middleware)
            continue
        end

        push!(
            dynamic_routes,
            DynamicRoute(route.handler, route.path, parsed.segments, parsed.param_names, route.is_middleware),
        )
    end

    dynamic_matcher = compile_dynamic_matcher(dynamic_routes)
    return MethodMatcher(dynamic_matcher, static_map)
end

function parse_route_pattern(path::String)
    parts = split(path, '/', keepempty = false)
    if isempty(parts)
        return (static = true, segments = String[], param_names = String[])
    end

    segments = String[]
    param_names = String[]
    is_static = true

    for part in parts
        push!(segments, String(part))
        if startswith(part, ":")
            is_static = false
            push!(param_names, part[2:end])
        elseif part == "*"
            is_static = false
            push!(param_names, "*")
        end
    end

    return (static = is_static, segments = segments, param_names = param_names)
end

function compile_dynamic_matcher(routes::Vector{DynamicRoute})::Function
    if isempty(routes)
        return empty_dynamic_matcher
    end

    trie = build_route_trie(routes)
    fn_expr = :((path::String) -> begin
        last = lastindex(path)
        index = route_start_index(path)
        $(trie_match_expression(trie))
        return nothing
    end)

    return RuntimeGeneratedFunctions.RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, fn_expr)
end

function build_route_trie(routes::Vector{DynamicRoute})::RouteTrieNode
    root = RouteTrieNode()
    for route in routes
        insert_route!(root, route)
    end
    return root
end

function insert_route!(root::RouteTrieNode, route::DynamicRoute)
    node = root
    for segment in route.segments
        if segment == "*"
            push!(node.wildcard_routes, route)
            return
        elseif startswith(segment, ":")
            node.param_child === nothing && (node.param_child = RouteTrieNode())
            node = node.param_child::RouteTrieNode
        else
            node = get_or_create_static_child!(node, segment)
        end
    end
    push!(node.terminal_routes, route)
end

function get_or_create_static_child!(node::RouteTrieNode, segment::String)::RouteTrieNode
    for child in node.static_children
        child.first == segment && return child.second
    end

    child = RouteTrieNode()
    push!(node.static_children, segment => child)
    return child
end

function trie_match_expression(node::RouteTrieNode, capture_syms::Vector{Symbol} = Symbol[])
    ended_branch = Any[]
    if !isempty(node.terminal_routes)
        push!(ended_branch, terminal_routes_expression(node, capture_syms))
    end
    if !isempty(node.wildcard_routes)
        push!(ended_branch, wildcard_routes_expression(node, capture_syms, :index, :last))
    end
    push!(ended_branch, :(nothing))

    body = trie_node_body_expression(node, capture_syms)
    return Expr(
        :block,
        quote
            if index > last
                $(Expr(:block, ended_branch...))
            else
                $body
            end
        end,
    )
end

function trie_node_body_expression(node::RouteTrieNode, capture_syms::Vector{Symbol})
    inner = Any[
        :(seg_start = bounds[1]),
        :(seg_stop = bounds[2]),
        :(next_index = bounds[3]),
        :(segment = SubString(path, seg_start, seg_stop)),
    ]

    for (literal, child) in node.static_children
        push!(
            inner,
            quote
                if segment == $(literal)
                    index = next_index
                    $(trie_match_expression(child, capture_syms))
                end
            end,
        )
    end

    if node.param_child !== nothing
        capture = gensym(:param)
        next_capture_syms = copy(capture_syms)
        push!(next_capture_syms, capture)
        push!(
            inner,
            quote
                $capture = segment
                index = next_index
                $(trie_match_expression(node.param_child::RouteTrieNode, next_capture_syms))
            end,
        )
    end

    if !isempty(node.wildcard_routes)
        push!(inner, wildcard_routes_expression(node, capture_syms, :index, :last))
    end

    push!(inner, :(nothing))
    return Expr(
        :block,
        :(bounds = segment_bounds(path, index)),
        quote
            if bounds === nothing
                nothing
            else
                $(Expr(:block, inner...))
            end
        end,
    )
end

function terminal_routes_expression(node::RouteTrieNode, capture_syms::Vector{Symbol})
    statements = Any[]
    for route in node.terminal_routes
        push!(statements, route_return_expression(route, capture_syms))
    end
    return Expr(:block, statements...)
end

function wildcard_routes_expression(node::RouteTrieNode, capture_syms::Vector{Symbol}, index_sym::Symbol, last_sym::Symbol)
    statements = Any[]
    for route in node.wildcard_routes
        wildcard_capture = gensym(:wildcard)
        next_capture_syms = copy(capture_syms)
        push!(next_capture_syms, wildcard_capture)
        push!(statements, route_wildcard_expression(route, next_capture_syms, wildcard_capture, index_sym, last_sym))
    end
    return Expr(:block, statements...)
end

function route_return_expression(route::DynamicRoute, capture_syms::Vector{Symbol})
    params_exprs = [:(params[$(name)] = String($sym)) for (name, sym) in zip(route.param_names, capture_syms)]
    return quote
        params = RouteParams()
        sizehint!(params, $(length(route.param_names)))
        $(Expr(:block, params_exprs...))
        return MatchedRoute($(route.handler), $(route.path), params)
    end
end

function route_wildcard_expression(
    route::DynamicRoute,
    capture_syms::Vector{Symbol},
    wildcard_capture::Symbol,
    index_sym::Symbol,
    last_sym::Symbol,
)
    params_exprs = [:(params[$(name)] = String($sym)) for (name, sym) in zip(route.param_names, capture_syms)]
    return quote
        $wildcard_capture = if $index_sym > $last_sym
            ""
        else
            SubString(path, $index_sym, $last_sym)
        end
        params = RouteParams()
        sizehint!(params, $(length(route.param_names)))
        $(Expr(:block, params_exprs...))
        return MatchedRoute($(route.handler), $(route.path), params)
    end
end

@inline function segment_bounds(path::String, index::Int)
    last = lastindex(path)
    index > last && return nothing
    path[index] == '/' && return nothing

    slash = findnext(==('/'), path, index)
    stop = slash === nothing ? last : prevind(path, slash)
    next_index = slash === nothing ? last + 1 : nextind(path, slash)
    return (index, stop, next_index, slash !== nothing)
end

@inline function route_start_index(path::String)
    first = firstindex(path)
    return nextind(path, first)
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
