"""
    Context(req; params = RouteParams())

Request-scoped context passed to handlers and middleware.
"""
mutable struct Context
    req::HTTP.Request
    params::RouteParams
    status::Int
    headers::Dict{String,String}
    body::Any
    cookies_out::Vector{HTTP.Cookies.Cookie}
    state::Dict{Symbol,Any}
end

function Context(req::HTTP.Request; params::RouteParams = RouteParams())
    return Context(req, params, 200, Dict{String,String}(), "", HTTP.Cookies.Cookie[], Dict{Symbol,Any}())
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
    for cookie in HTTP.Cookies.cookies(accessor.ctx.req)
        cookie.name == key && return cookie.value
    end
    return default
end

function Base.getproperty(ctx::Context, name::Symbol)
    if name in (:req, :params, :status, :headers, :body, :cookies_out, :state)
        return getfield(ctx, name)
    elseif name == :cookie
        return CookieAccessor(ctx)
    elseif name == :setcookie
        return (args...; kwargs...) -> setcookie(ctx, args...; kwargs...)
    elseif name == :reqtext
        return () -> reqtext(ctx)
    elseif name == :reqjson
        return () -> reqjson(ctx)
    elseif name == :reqform
        return () -> reqform(ctx)
    elseif name == :reqquery
        return () -> reqquery(ctx)
    end
    return getproperty(getfield(ctx, :req), name)
end

Base.getindex(ctx::Context, key::AbstractString) = ctx.params[String(key)]
Base.get(ctx::Context, key::AbstractString, default = nothing) = get(ctx.params, String(key), default)

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
    setcookie(ctx, name, value; kwargs...)

Append a `Set-Cookie` header to the response.
"""
function setcookie(ctx::Context, name::AbstractString, value; kwargs...)::Context
    cookie = HTTP.Cookies.Cookie(String(name), string(value); kwargs...)
    push!(ctx.cookies_out, cookie)
    return ctx
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

request_body_text(ctx::Context)::String = String(ctx.req.body)

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

function Base.get(ctx::Context, key::Symbol, default = nothing)
    return get(ctx.state, key, default)
end

function to_response(ctx::Context)::HTTP.Response
    response = HTTP.Response(ctx.status, collect(pairs(ctx.headers)), ctx.body)
    for cookie in ctx.cookies_out
        HTTP.Cookies.addcookie!(response, cookie)
    end
    return response
end
