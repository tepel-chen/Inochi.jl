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
    path = request_path(req.target)
    matcher = get_matcher(app, req.method)
    final_match = match_final_route(matcher, path)
    base_params = final_match === nothing ? EMPTY_ROUTE_PARAMS : matched_params(final_match)
    ctx = Context(app, req; params = base_params)
    middleware_stack = collect_middlewares(app, req.method, path, final_match)
    if isempty(middleware_stack)
        try
            ctx.final_match = final_match
            ctx.middleware_chain = EMPTY_MIDDLEWARE_MATCHES
            ctx.middleware_index = 1
            ctx.middleware_called = false
            final_match === nothing && return handle_notfound(app, ctx)
            ctx.params = matched_params(final_match)
            return to_response(matched_handler(final_match)(ctx), ctx)
        catch err
            ctx.backtrace = catch_backtrace()
            return handle_error(app, ctx, err)
        end
    end

    try
        ctx.middleware_chain = middleware_stack
        ctx.middleware_index = 1
        ctx.middleware_called = false
        ctx.final_match = final_match
        return continue_dispatch(ctx)
    catch err
        ctx.backtrace = catch_backtrace()
        return handle_error(app, ctx, err)
    end
end

function request_path(target::AbstractString)::String
    isempty(target) && return "/"

    first = firstindex(target)
    target[first] == '/' || return normalize_path(String(HTTP.URIs.URI(target).path))

    for index in eachindex(target)
        char = target[index]
        if char == '?' || char == '#'
            index == first && return "/"
            return String(SubString(target, first, prevind(target, index)))
        end
    end

    return target isa String ? target : String(target)
end

function get_matcher(app::App, method::AbstractString)::MethodMatcher
    app.dirty && compile_routes!(app)
    return get(app.matchers, uppercase(String(method)), EMPTY_METHOD_MATCHER)
end

function get_middleware_matcher(app::App, method::AbstractString)::MiddlewareMatcher
    app.dirty && compile_routes!(app)
    return get(app.middleware_matchers, uppercase(String(method)), EMPTY_MIDDLEWARE_MATCHER)
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
@inline matched_params(::StaticRoute) = EMPTY_ROUTE_PARAMS
@inline matched_params(match::MatchedRoute) = match.params
@inline matched_middleware_routes(match::StaticRoute) = match.middleware_routes
@inline matched_middleware_routes(match::MatchedRoute) = match.middleware_routes
@inline matched_middleware_routes(::Nothing) = EMPTY_MIDDLEWARE_ROUTES

function compile_routes!(app::App)::App
    grouped_routes = Dict{String,Vector{RouteDefinition}}()
    grouped_middleware_routes = Dict{String,Vector{MiddlewareRoute}}()
    order = 0
    for route in app.routes
        order += 1
        if route.method == "ALL"
            for method in SUPPORTED_HTTP_METHODS
                push!(
                    get!(grouped_routes, method, RouteDefinition[]),
                    RouteDefinition(method, route.path, route.handler, route.is_middleware),
                )
                if route.is_middleware
                    push!(
                        get!(grouped_middleware_routes, method, MiddlewareRoute[]),
                        MiddlewareRoute(route.handler, route.path, normalize_middleware_prefix(route.path), order),
                    )
                end
            end
        else
            push!(get!(grouped_routes, route.method, RouteDefinition[]), route)
            if route.is_middleware
                push!(
                    get!(grouped_middleware_routes, route.method, MiddlewareRoute[]),
                    MiddlewareRoute(route.handler, route.path, normalize_middleware_prefix(route.path), order),
                )
            end
        end
    end

    empty!(app.matchers)
    empty!(app.middleware_matchers)
    for (method, routes) in grouped_routes
        app.matchers[method] = build_method_matcher(routes, get(grouped_middleware_routes, method, EMPTY_MIDDLEWARE_ROUTES))
    end
    for (method, routes) in grouped_middleware_routes
        app.middleware_matchers[method] = build_middleware_matcher(routes)
    end

    app.dirty = false
    return app
end

function build_method_matcher(routes::Vector{RouteDefinition}, middleware_routes::Vector{MiddlewareRoute})::MethodMatcher
    static_map = Dict{String,StaticRoute}()
    dynamic_routes = DynamicRoute[]

    for route in routes
        route.is_middleware && continue

        parsed = parse_route_pattern(route.path)
        route_middleware_routes = route_middleware_candidates(route.path, middleware_routes)
        if parsed.static
            static_map[route.path] = StaticRoute(route.handler, route.path, route.is_middleware, route_middleware_routes)
            continue
        end

        push!(
            dynamic_routes,
            DynamicRoute(route.handler, route.path, parsed.segments, parsed.param_names, route.is_middleware, route_middleware_routes),
        )
    end

    dynamic_matcher = compile_dynamic_matcher(dynamic_routes)
    return MethodMatcher(dynamic_matcher, static_map)
end

function route_middleware_candidates(path::String, middleware_routes::Vector{MiddlewareRoute})::Vector{MiddlewareRoute}
    isempty(middleware_routes) && return EMPTY_MIDDLEWARE_ROUTES
    route_prefix = route_static_prefix(path)
    candidates = MiddlewareRoute[]
    for route in middleware_routes
        route.prefix == "/" || continue
        route_prefix_may_match(route_prefix, route.prefix) && push!(candidates, route)
    end
    for route in middleware_routes
        route.prefix == "/" && continue
        route_prefix_may_match(route_prefix, route.prefix) && push!(candidates, route)
    end
    return isempty(candidates) ? EMPTY_MIDDLEWARE_ROUTES : candidates
end

function route_static_prefix(path::String)::String
    path == "/" && return "/"
    parts = split(path, '/', keepempty = false)
    prefix_parts = String[]
    for part in parts
        startswith(part, ":") && break
        part == "*" && break
        push!(prefix_parts, String(part))
    end
    return isempty(prefix_parts) ? "/" : "/" * join(prefix_parts, "/")
end

function route_prefix_may_match(route_prefix::String, middleware_prefix::String)::Bool
    path_prefix_matches(route_prefix, middleware_prefix) && return true
    path_prefix_matches(middleware_prefix, route_prefix) && return true
    return false
end

function path_prefix_matches(path::String, prefix::String)::Bool
    prefix == "/" && return true
    path == "/" && return false

    path_parts = split(path, '/', keepempty = false)
    prefix_parts = split(prefix, '/', keepempty = false)
    length(path_parts) < length(prefix_parts) && return false

    for index in eachindex(prefix_parts)
        path_parts[index] == prefix_parts[index] || return false
    end

    return true
end

function build_middleware_matcher(routes::Vector{MiddlewareRoute})::MiddlewareMatcher
    if isempty(routes)
        return EMPTY_MIDDLEWARE_MATCHER
    end

    global_routes = MiddlewareRoute[]
    scoped_routes = MiddlewareRoute[]
    for route in routes
        if route.prefix == "/"
            push!(global_routes, route)
        else
            push!(scoped_routes, route)
        end
    end

    sort!(global_routes, by = route -> route.order)

    middleware_matcher = if isempty(scoped_routes)
        empty_middleware_matcher
    else
        trie = build_middleware_trie(scoped_routes)
        finalize_middleware_trie!(trie, MiddlewareRoute[])
        fn_expr = :((path::String, final_path::Union{Nothing,String}, matches::Vector{MiddlewareMatch}, write_index::Int) -> begin
            last = lastindex(path)
            index = route_start_index(path)
            $(middleware_trie_expression(trie))
            return write_index
        end)
        RuntimeGeneratedFunctions.RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, fn_expr)
    end

    return MiddlewareMatcher(global_routes, length(routes), middleware_matcher)
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

function build_middleware_trie(routes::Vector{MiddlewareRoute})::MiddlewareTrieNode
    root = MiddlewareTrieNode()
    for route in routes
        insert_middleware_route!(root, route)
    end
    return root
end

function finalize_middleware_trie!(node::MiddlewareTrieNode, inherited::Vector{MiddlewareRoute})
    node_ordered = copy(inherited)
    if !isempty(node.terminal_routes)
        terminal_routes = sort(copy(node.terminal_routes), by = route -> route.order)
        append!(node_ordered, terminal_routes)
    end
    node.ordered_routes = node_ordered
    for child in node.static_children
        finalize_middleware_trie!(child.second, node_ordered)
    end
    return node
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

function insert_middleware_route!(root::MiddlewareTrieNode, route::MiddlewareRoute)
    node = root
    if route.prefix != "/"
        for segment in split(route.prefix, '/', keepempty = false)
            node = get_or_create_middleware_child!(node, String(segment))
        end
    end
    push!(node.terminal_routes, route)
end

function get_or_create_middleware_child!(node::MiddlewareTrieNode, segment::String)::MiddlewareTrieNode
    for child in node.static_children
        child.first == segment && return child.second
    end

    child = MiddlewareTrieNode()
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
        return MatchedRoute($(route.handler), $(route.path), params, $(route.middleware_routes))
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
        return MatchedRoute($(route.handler), $(route.path), params, $(route.middleware_routes))
    end
end

function middleware_trie_expression(node::MiddlewareTrieNode)
    return quote
        if index > last
            return middleware_emit_matches($(node.ordered_routes), path, index, last, final_path, matches, write_index)
        end

        bounds = segment_bounds(path, index)
        if bounds === nothing
            return middleware_emit_matches($(node.ordered_routes), path, index, last, final_path, matches, write_index)
        end

        seg_start = bounds[1]
        seg_stop = bounds[2]
        next_index = bounds[3]
        segment = SubString(path, seg_start, seg_stop)

        $(Expr(:block, [quote
            if segment == $(literal)
                index = next_index
                return $(middleware_trie_expression(child))
            end
        end for (literal, child) in node.static_children]...))

        return middleware_emit_matches($(node.ordered_routes), path, index, last, final_path, matches, write_index)
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

function continue_dispatch(ctx::Context)::HTTP.Response
    middlewares = ctx.middleware_chain
    middlewares === nothing && throw(ArgumentError("dispatch state missing middleware chain"))

    index = ctx.middleware_index
    if index > length(middlewares)
        ctx.final_match === nothing && return handle_notfound(ctx.app, ctx)
        ctx.params = matched_params(ctx.final_match)
        return to_response(matched_handler(ctx.final_match)(ctx), ctx)
    end

    middleware = middlewares[index]
    original_params = ctx.params
    ctx.params = middleware.params
    ctx.middleware_called = false
    try
        return to_response(middleware.handler(ctx), ctx)
    finally
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

function collect_middlewares(routes::Vector{MiddlewareRoute}, path::String, final_match)
    isempty(routes) && return EMPTY_MIDDLEWARE_MATCHES
    final_path = final_match === nothing ? nothing : matched_path(final_match)
    middlewares = Vector{MiddlewareMatch}(undef, length(routes))
    write_index = middleware_emit_candidate_matches(routes, path, final_path, middlewares, 1)
    write_index == 1 && return EMPTY_MIDDLEWARE_MATCHES
    resize!(middlewares, write_index - 1)
    return middlewares
end

function collect_middlewares(app::App, method::AbstractString, path::String, final_match)
    if final_match === nothing
        matcher = get_middleware_matcher(app, method)
        final_path = nothing
        return collect_middlewares(matcher, path, final_path)
    end
    return collect_middlewares(matched_middleware_routes(final_match), path, final_match)
end

function collect_middlewares(matcher::MiddlewareMatcher, path::String, final_path::Union{Nothing,String})
    matcher.route_count == 0 && return EMPTY_MIDDLEWARE_MATCHES

    middlewares = Vector{MiddlewareMatch}(undef, matcher.route_count)
    write_index = 1
    !isempty(matcher.global_routes) &&
        (write_index = middleware_emit_matches(matcher.global_routes, path, route_start_index(path), lastindex(path), final_path, middlewares, write_index))
    write_index = matcher.middleware_matcher(path, final_path, middlewares, write_index)
    write_index == 1 && return EMPTY_MIDDLEWARE_MATCHES
    resize!(middlewares, write_index - 1)
    return middlewares
end

function normalize_middleware_prefix(path::String)::String
    if path == "/" || path == "/*"
        return "/"
    elseif endswith(path, "/*")
        prefix = path[1:end-2]
        return isempty(prefix) ? "/" : prefix
    elseif length(path) > 1 && endswith(path, "/")
        return path[1:end-1]
    else
        return path
    end
end

function empty_middleware_matcher(path::String, final_path::Union{Nothing,String}, matches::Vector{MiddlewareMatch}, write_index::Int)
    return write_index
end

function middleware_emit_matches(routes::Vector{MiddlewareRoute}, path::String, index::Int, last::Int, final_path::Union{Nothing,String}, matches::Vector{MiddlewareMatch}, write_index::Int)
    tail = index > last ? "" : String(SubString(path, index, last))
    for route in routes
        final_path !== nothing && route.path == final_path && continue
        matches[write_index] = MiddlewareMatch(route.handler, route.path, MiddlewareParams(tail), route.order)
        write_index += 1
    end
    return write_index
end

function middleware_emit_candidate_matches(routes::Vector{MiddlewareRoute}, path::String, final_path::Union{Nothing,String}, matches::Vector{MiddlewareMatch}, write_index::Int)
    for route in routes
        final_path !== nothing && route.path == final_path && continue
        tail = middleware_tail(path, route.prefix)
        tail === nothing && continue
        matches[write_index] = MiddlewareMatch(route.handler, route.path, MiddlewareParams(tail), route.order)
        write_index += 1
    end
    return write_index
end

function middleware_tail(path::String, prefix::String)::Union{Nothing,String}
    if prefix == "/"
        start = route_start_index(path)
        return start > lastindex(path) ? "" : String(SubString(path, start, lastindex(path)))
    end

    startswith(path, prefix) || return nothing

    prefix_last = lastindex(prefix)
    path_last = lastindex(path)
    prefix_last == path_last && return ""

    next_index = nextind(path, prefix_last)
    next_index > path_last && return ""
    path[next_index] == '/' || return nothing

    tail_start = nextind(path, next_index)
    tail_start > path_last && return ""
    return String(SubString(path, tail_start, path_last))
end

const EMPTY_MIDDLEWARE_MATCHER = MiddlewareMatcher(MiddlewareRoute[], 0, empty_middleware_matcher)
