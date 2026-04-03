"""
    basicAuth(; username, password, realm="Restricted")

Create middleware that protects a route with HTTP Basic authentication.
"""
function basicAuth(; username::AbstractString, password::AbstractString, realm::AbstractString = "Restricted")
    expected = String(username) * ":" * String(password)

    return function (ctx::Context)
        authorization = HTTP.header(ctx.req, "Authorization", "")

        if startswith(authorization, "Basic ")
            encoded = authorization[7:end]
            try
                decoded = String(base64decode(encoded))
                if constant_time_equals(decoded, expected)
                    return ctx.next()
                end
            catch
            end
        end

        status!(ctx, 401)
        header!(ctx, "WWW-Authenticate", "Basic realm=\"" * String(realm) * "\"")
        body!(ctx, "Unauthorized")
        return ctx
    end
end
