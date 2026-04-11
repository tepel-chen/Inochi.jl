"""
    basicAuth(; username, password, realm="Restricted")

Create middleware that protects a route with HTTP Basic authentication.
"""
function basicAuth(; username::AbstractString, password::AbstractString, realm::AbstractString = "Restricted")
    expected = username * ":" * password

    return function (ctx::Context)
        authorization = get(ctx.req.headers, "Authorization", "")

        if startswith(authorization, "Basic ")
            encoded = authorization[7:end]
            decoded = String(base64decode(encoded))
            if constant_time_equals(decoded, expected)
                return next(ctx)
            end
        end

        status!(ctx, 401)
        header!(ctx, "WWW-Authenticate", "Basic realm=\"" * realm * "\"")
        body!(ctx, "Unauthorized")
        return ctx
    end
end
