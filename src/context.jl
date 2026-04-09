"""
    Context(app, req; params = RouteParams())

Request-scoped context passed to handlers and middleware.
"""
mutable struct Context
    app::App
    req::HTTP.Request
    params::Any
    status::Int
    headers::Dict{String,String}
    body::Any
    response::Union{Nothing,HTTP.Response}
    cookies_out::Vector{HTTP.Cookies.Cookie}
    state::Dict{Symbol,Any}
    varies_on_cookie::Bool
    middleware_chain::Any
    middleware_index::Int
    middleware_called::Bool
    final_match::Any
    backtrace::Any
end

function Context(app::App, req::HTTP.Request; params = RouteParams())
    return Context(
        app,
        req,
        params,
        200,
        Dict{String,String}(),
        "",
        nothing,
        HTTP.Cookies.Cookie[],
        Dict{Symbol,Any}(),
        false,
        nothing,
        1,
        false,
        nothing,
        nothing,
    )
end

struct CookieAccessor
    ctx::Context
end

function Base.getindex(accessor::CookieAccessor, key::AbstractString)
    value = accessor(String(key))
    value === nothing && throw(KeyError(key))
    return value
end

function (accessor::CookieAccessor)(key::AbstractString, default = nothing)
    accessor.ctx.varies_on_cookie = true
    for cookie in HTTP.Cookies.cookies(accessor.ctx.req)
        cookie.name == key && return cookie.value
    end
    return default
end

function Base.getproperty(ctx::Context, name::Symbol)
    if name in (
        :app,
        :req,
        :params,
        :status,
        :headers,
        :body,
        :cookies_out,
        :state,
        :varies_on_cookie,
        :middleware_chain,
        :middleware_index,
        :middleware_called,
        :final_match,
        :backtrace,
    )
        return getfield(ctx, name)
    end
    return getproperty(getfield(ctx, :req), name)
end

Base.getindex(ctx::Context, key::AbstractString) = ctx.params[String(key)]
"""
    Base.get(ctx, key::AbstractString, default = nothing)

Read a route parameter from `ctx.params`.
"""
Base.get(ctx::Context, key::AbstractString, default = nothing) = get(ctx.params, String(key), default)

Base.getindex(params::MiddlewareParams, key::AbstractString) = key == "*" ? params.tail : throw(KeyError(key))
Base.get(params::MiddlewareParams, key::AbstractString, default = nothing) = key == "*" ? params.tail : default

"""
    status!(ctx, code)

Set the response status code.
"""
function status!(ctx::Context, code::Integer)::Context
    ctx.status = Int(code)
    return ctx
end

"""
    header!(ctx, key, value)

Set a response header.
"""
function header!(ctx::Context, key::AbstractString, value)::Context
    ctx.headers[String(key)] = string(value)
    return ctx
end

"""
    body!(ctx, value)

Set the raw response body.
"""
function body!(ctx::Context, value)::Context
    ctx.body = value
    return ctx
end

"""
    response!(ctx, response)

Store a raw `HTTP.Response` on the context and sync the visible status/body.
"""
function response!(ctx::Context, response::HTTP.Response)::Context
    setfield!(ctx, :response, response)
    setfield!(ctx, :status, Int(response.status))
    setfield!(ctx, :body, response.body)
    return ctx
end

"""
    setcookie(ctx, name, value; kwargs...)

Append a `Set-Cookie` header to the response.
"""
function setcookie(ctx::Context, name::AbstractString, value; kwargs...)::Context
    cookie_kwargs = Pair{Symbol,Any}[]
    for (key, val) in pairs(NamedTuple(kwargs))
        key === :samesite && val === nothing && continue
        push!(cookie_kwargs, key => val)
    end
    cookie = HTTP.Cookies.Cookie(String(name), string(value); cookie_kwargs...)
    push!(ctx.cookies_out, cookie)
    return ctx
end

"""
    cookie(ctx)
    cookie(ctx, key, default = nothing)

Return a request cookie accessor, or read a request cookie directly.
"""
cookie(ctx::Context) = CookieAccessor(ctx)
cookie(ctx::Context, key::AbstractString, default = nothing) = cookie(ctx)(key, default)

function app_config_string(app::App, key::AbstractString)::Union{Nothing,String}
    value = get(app.config, String(key), nothing)
    return value isa String ? value : nothing
end

function app_config_int(app::App, key::AbstractString, default::Integer)::Int
    value = get(app.config, String(key), Int(default))
    value isa Int || throw(ArgumentError("app.config[$(repr(String(key)))] must be an Int"))
    return value
end

function constant_time_equals(left::AbstractString, right::AbstractString)::Bool
    ncodeunits(left) == ncodeunits(right) || return false
    diff = UInt8(0)
    @inbounds for index in eachindex(codeunits(left), codeunits(right))
        diff |= codeunits(left)[index] ⊻ codeunits(right)[index]
    end
    return diff == 0
end

function secure_cookie_signature(secret::AbstractString, value::AbstractString)::String
    return bytes2hex(hmac_sha256(Vector{UInt8}(codeunits(secret)), value))
end

"""
    secure_cookie(ctx, name; secret = nothing, default = nothing)

Read and verify a signed cookie formatted as `<BASE64>.<HMAC>`.
"""
function secure_cookie(ctx::Context, name::AbstractString; secret = nothing, default = nothing)
    raw_value = cookie(ctx, String(name), nothing)
    raw_value === nothing && return default

    parts = split(raw_value, '.'; limit = 2)
    length(parts) == 2 || return default
    payload, signature = parts
    resolved_secret = resolve_cookie_secret(ctx, secret)

    constant_time_equals(signature, secure_cookie_signature(resolved_secret, payload)) || return default
    return String(base64decode(payload))
end

"""
    set_secure_cookie(ctx, name, value; secret = nothing, kwargs...)

Set a signed cookie formatted as `<BASE64>.<HMAC>`.
"""
function set_secure_cookie(ctx::Context, name::AbstractString, value; secret = nothing, kwargs...)::Context
    payload = base64encode(String(value))
    signature = secure_cookie_signature(resolve_cookie_secret(ctx, secret), payload)
    return setcookie(ctx, name, payload * "." * signature; kwargs...)
end

function resolve_cookie_secret(ctx::Context, secret)::String
    if secret !== nothing
        return String(secret)
    elseif (configured = app_config_string(ctx.app, "secret")) !== nothing
        return configured
    else
        throw(ArgumentError("No app.config[\"secret\"] configured for secure cookies"))
    end
end

function request_content_type(ctx::Context)::String
    raw = strip(HTTP.header(ctx.req, "Content-Type", ""))
    isempty(raw) && return ""
    return lowercase(strip(first(split(raw, ';'; limit = 2))))
end

function require_content_type(ctx::Context, expected::AbstractString, description::AbstractString)::Nothing
    actual = request_content_type(ctx)
    actual == expected && return nothing
    throw(ArgumentError("Expected Content-Type $(expected) for $(description), got " * (isempty(actual) ? "<missing>" : actual)))
end

function request_body_text(ctx::Context)::String
    return String(request_body_bytes(ctx))
end

function request_body_bytes(ctx::Context)::Vector{UInt8}
    max_content_size = app_config_int(ctx.app, "max_content_size", DEFAULT_MAX_CONTENT_SIZE)
    body_bytes = Vector{UInt8}(ctx.req.body)
    length(body_bytes) <= max_content_size || throw(ArgumentError("Request body exceeds max_content_size"))
    return body_bytes
end

"""
    reqtext(ctx)

Read the request body as text. Requires a `text/*` content type.
"""
function reqtext(ctx::Context)::String
    actual = request_content_type(ctx)
    startswith(actual, "text/") || throw(ArgumentError("Expected Content-Type text/* for reqtext, got " * (isempty(actual) ? "<missing>" : actual)))
    return request_body_text(ctx)
end

"""
    reqjson(ctx)

Parse the request body as JSON. Requires `application/json` or `*+json`.
"""
function reqjson(ctx::Context)
    actual = request_content_type(ctx)
    valid = actual == "application/json" || endswith(actual, "+json")
    valid || throw(ArgumentError("Expected Content-Type application/json for reqjson, got " * (isempty(actual) ? "<missing>" : actual)))
    return JSON.parse(request_body_text(ctx))
end

"""
    reqmultipart(ctx)

Parse the request body as multipart form data and return the parsed parts.
"""
function reqmultipart(ctx::Context)::Vector{HTTP.Multipart}
    require_content_type(ctx, "multipart/form-data", "reqmultipart")
    request_body_bytes(ctx)
    parts = HTTP.parse_multipart_form(ctx.req)
    parts === nothing && throw(ArgumentError("Failed to parse multipart/form-data request"))
    return parts
end

"""
    reqfile(ctx; name = nothing)

Return the first uploaded multipart file part, optionally matching a field name.
"""
function reqfile(ctx::Context; name::Union{Nothing,AbstractString} = nothing)
    parts = reqmultipart(ctx)
    target_name = name === nothing ? nothing : String(name)
    for part in parts
        part.filename === nothing && continue
        if target_name === nothing || part.name == target_name
            return part
        end
    end
    return nothing
end

"""
    reqform(ctx)

Parse the request body as `application/x-www-form-urlencoded`.
"""
function reqform(ctx::Context)::Dict{String,String}
    require_content_type(ctx, "application/x-www-form-urlencoded", "reqform")
    return Dict{String,String}(HTTP.URIs.queryparams(request_body_text(ctx)))
end

"""
    reqquery(ctx)

Return parsed query parameters from the request URL.
"""
function reqquery(ctx::Context)::Dict{String,String}
    uri = HTTP.URIs.URI(ctx.req.target)
    return Dict{String,String}(HTTP.URIs.queryparams(uri))
end

function resolve_renderer(ctx::Context)::Function
    ctx.app.renderer !== nothing || throw(ArgumentError("No app.renderer configured"))
    return ctx.app.renderer
end

function resolve_file_renderer(ctx::Context)::Function
    if ctx.app.file_renderer !== nothing
        return ctx.app.file_renderer
    end
    return (filepath, data) -> resolve_renderer(ctx)(read(filepath, String), data)
end

function resolve_views_root(ctx::Context)::String
    if ctx.app.views !== nothing
        return ctx.app.views
    end
    return joinpath(executable_root(), "views")
end

"""
    render_text(ctx, template, data = Dict())

Render an inline template with the application's configured renderer and return HTML.
"""
function render_text(ctx::Context, template::AbstractString, data = Dict{String,Any}())::Context
    rendered = resolve_renderer(ctx)(String(template), data)
    return html(ctx, String(rendered))
end

"""
    render(ctx, filename, data = Dict())

Render a template file from `app.views` with the application's configured renderer and return HTML.
"""
function render(ctx::Context, filename::AbstractString, data = Dict{String,Any}())::Context
    template_path = safe_join(resolve_views_root(ctx), filename)
    template_path === nothing && throw(ArgumentError("Template path escapes app.views"))
    isfile(template_path) || throw(ArgumentError("Template not found: " * String(filename)))
    rendered = resolve_file_renderer(ctx)(template_path, data)
    return html(ctx, String(rendered))
end

"""
    next(ctx)

Continue to the next middleware or final route.
"""
function next(ctx::Context)
    middleware_chain = getfield(ctx, :middleware_chain)
    middleware_chain === nothing && throw(ArgumentError("next() is only available inside middleware"))
    ctx.middleware_called && throw(ArgumentError("next() may only be called once per middleware"))
    ctx.middleware_called = true
    ctx.middleware_index += 1
    return continue_dispatch(ctx)
end

"""
    text(ctx, value; status = ctx.status)

Write a plain-text response.
"""
function text(ctx::Context, value::AbstractString; status::Integer = ctx.status)::Context
    status!(ctx, status)
    header!(ctx, "Content-Type", "text/plain; charset=utf-8")
    body!(ctx, String(value))
    return ctx
end

"""
    html(ctx, value; status = ctx.status)

Write an HTML response.
"""
function html(ctx::Context, value::AbstractString; status::Integer = ctx.status)::Context
    status!(ctx, status)
    header!(ctx, "Content-Type", "text/html; charset=utf-8")
    body!(ctx, String(value))
    return ctx
end

"""
    json(ctx, value; status = ctx.status)

Write a JSON response.
"""
function json(ctx::Context, value; status::Integer = ctx.status)::Context
    status!(ctx, status)
    header!(ctx, "Content-Type", "application/json; charset=utf-8")
    body!(ctx, JSON.json(value))
    return ctx
end

"""
    redirect(ctx, location; status = 303)

Write a redirect response with a `Location` header.
"""
function redirect(ctx::Context, location::AbstractString; status::Integer = 303)::Context
    status!(ctx, status)
    header!(ctx, "Location", String(location))
    body!(ctx, "")
    return ctx
end

"""
    set!(ctx, key, value)

Store arbitrary request-local state on the context.
"""
function set!(ctx::Context, key::Symbol, value)
    ctx.state[key] = value
    return value
end

"""
    Base.get(ctx, key::Symbol, default = nothing)

Read request-local state previously stored with `set!`.
"""
function Base.get(ctx::Context, key::Symbol, default = nothing)
    return get(ctx.state, key, default)
end

const SERVER_HEADER_NAME = "Server"
const SERVER_HEADER_VALUE = "Inochi/" * INOCHI_VERSION * " Julia/" * JULIA_VERSION
const DATE_HEADER_NAME = "Date"
const VARY_HEADER_NAME = "Vary"
const DEFAULT_VARY_VALUE = "Origin"
const HTTP_DATE_CACHE_KEYS = fill(typemin(Int64), Threads.nthreads())
const HTTP_DATE_CACHE_VALUES = fill("", Threads.nthreads())

function http_date(now::DateTime = now(UTC))::String
    cache_index = Threads.threadid()
    cache_key = Dates.value(now) ÷ 1000
    if HTTP_DATE_CACHE_KEYS[cache_index] == cache_key
        return HTTP_DATE_CACHE_VALUES[cache_index]
    end
    weekdays = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    weekday = weekdays[dayofweek(now)]
    month_name = months[month(now)]
    value = @sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", weekday, day(now), month_name, year(now), hour(now), minute(now), second(now))
    HTTP_DATE_CACHE_VALUES[cache_index] = value
    HTTP_DATE_CACHE_KEYS[cache_index] = cache_key
    return value
end

function merge_vary(existing::AbstractString, value::AbstractString)::String
    entries = String[]
    seen = Set{String}()

    for item in split(existing, ',')
        normalized = strip(item)
        isempty(normalized) && continue
        lowercase(normalized) in seen && continue
        push!(entries, normalized)
        push!(seen, lowercase(normalized))
    end

    normalized_value = strip(String(value))
    if !isempty(normalized_value) && !(lowercase(normalized_value) in seen)
        push!(entries, normalized_value)
    end

    return join(entries, ", ")
end

function apply_default_headers(response::HTTP.Response, ctx::Union{Nothing,Context} = nothing)::HTTP.Response
    HTTP.setheader(response, SERVER_HEADER_NAME => SERVER_HEADER_VALUE)
    HTTP.setheader(response, DATE_HEADER_NAME => http_date())
    existing_vary = HTTP.header(response, VARY_HEADER_NAME, "")
    if isempty(existing_vary)
        vary = DEFAULT_VARY_VALUE
        if ctx !== nothing && ctx.varies_on_cookie
            vary = DEFAULT_VARY_VALUE * ", Cookie"
        end
    else
        vary = merge_vary(existing_vary, DEFAULT_VARY_VALUE)
        if ctx !== nothing && ctx.varies_on_cookie
            vary = merge_vary(vary, "Cookie")
        end
    end
    HTTP.setheader(response, VARY_HEADER_NAME => vary)
    return response
end

function to_response(ctx::Context)::HTTP.Response
    getfield(ctx, :response) !== nothing && return getfield(ctx, :response)
    response = HTTP.Response(ctx.status, collect(pairs(ctx.headers)), ctx.body)
    for cookie in ctx.cookies_out
        HTTP.Cookies.addcookie!(response, cookie)
    end
    return apply_default_headers(response, ctx)
end

apply_result!(ctx::Context, result::Context) = begin
    result === ctx && return ctx
    getfield(result, :response) !== nothing && response!(ctx, getfield(result, :response))
    ctx.status = result.status
    ctx.headers = result.headers
    ctx.body = result.body
    ctx.cookies_out = result.cookies_out
    ctx.state = result.state
    ctx.varies_on_cookie = result.varies_on_cookie
    return ctx
end

apply_result!(ctx::Context, result::HTTP.Response) = begin
    response!(ctx, result)
    return ctx
end

apply_result!(ctx::Context, result::AbstractString) = html(ctx, result)
apply_result!(ctx::Context, result::AbstractVector{UInt8}) = body!(ctx, result)
apply_result!(ctx::Context, result) = throw(ArgumentError("Unsupported response body type: $(typeof(result))"))
