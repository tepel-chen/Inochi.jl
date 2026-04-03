const CSRF_COOKIE_NAME = "csrf_token"
const CSRF_HEADER_NAME = "X-CSRF-Token"
const CSRF_PARAM_NAME = "csrf_token"
const SAFE_HTTP_METHODS = Set(("GET", "HEAD", "OPTIONS", "TRACE"))

function resolve_samesite(value)
    isnothing(value) && return nothing

    normalized = lowercase(String(value))
    if normalized == "default"
        return HTTP.Cookies.SameSiteDefaultMode
    elseif normalized == "lax"
        return HTTP.Cookies.SameSiteLaxMode
    elseif normalized == "strict"
        return HTTP.Cookies.SameSiteStrictMode
    elseif normalized == "none"
        return HTTP.Cookies.SameSiteNoneMode
    end

    throw(ArgumentError("Invalid SameSite value: " * repr(value)))
end

function generate_csrf_token()::String
    bytes = rand(RandomDevice(), UInt8, 32)
    return base64encode(bytes)
end

function csrf_token(ctx::Context)::String
    token = get(ctx, :csrf_token, nothing)
    token isa AbstractString && return String(token)

    existing = ctx.cookie(CSRF_COOKIE_NAME, nothing)
    if existing isa AbstractString
        resolved = String(existing)
        set!(ctx, :csrf_token, resolved)
        return resolved
    end

    generated = generate_csrf_token()
    set!(ctx, :csrf_token, generated)
    return generated
end

function csrf_request_token(ctx::Context)
    header_token = HTTP.header(ctx.req, CSRF_HEADER_NAME, "")
    isempty(header_token) || return header_token

    query_token = get(reqquery(ctx), CSRF_PARAM_NAME, nothing)
    query_token !== nothing && return query_token

    if request_content_type(ctx) == "application/x-www-form-urlencoded"
        return get(reqform(ctx), CSRF_PARAM_NAME, nothing)
    end

    return nothing
end

"""
    csrf(; cookie_name="csrf_token", httponly=false, secure=false, samesite="Lax", path="/")

Create middleware that issues a CSRF token cookie and validates it on unsafe methods.

The middleware stores the current token in `ctx.state[:csrf_token]`. Rendering the
token into forms or requests is left to the application.
"""
function csrf(; cookie_name::AbstractString = CSRF_COOKIE_NAME, httponly::Bool = false, secure::Bool = false, samesite = "Lax", path::AbstractString = "/")
    resolved_cookie_name = String(cookie_name)
    resolved_samesite = resolve_samesite(samesite)

    return function (ctx::Context, next::Function)
        token = ctx.cookie(resolved_cookie_name, nothing)
        if !(token isa AbstractString) || isempty(token)
            token = generate_csrf_token()
            ctx.setcookie(resolved_cookie_name, token; httponly = httponly, secure = secure, samesite = resolved_samesite, path = String(path))
        else
            token = String(token)
        end
        set!(ctx, :csrf_token, token)

        if uppercase(ctx.method) in SAFE_HTTP_METHODS
            return next()
        end

        request_token = csrf_request_token(ctx)
        if request_token isa AbstractString && constant_time_equals(String(request_token), token)
            return next()
        end

        status!(ctx, 403)
        body!(ctx, "Forbidden")
        return ctx
    end
end
