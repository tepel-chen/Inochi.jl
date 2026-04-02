"""
    cors(; origin="*", methods=nothing, headers="*", expose_headers=nothing, credentials=false, max_age=nothing)

Create middleware that adds common CORS headers.
"""
function cors(; origin::AbstractString = "*", methods = nothing, headers::AbstractString = "*", expose_headers = nothing, credentials::Bool = false, max_age = nothing)
    allowed_methods = methods === nothing ? join(SUPPORTED_HTTP_METHODS, ", ") : string(methods)
    exposed_headers = expose_headers === nothing ? nothing : string(expose_headers)
    max_age_value = max_age === nothing ? nothing : string(max_age)

    return function (ctx::Context, next::Function)
        header!(ctx, "Access-Control-Allow-Origin", origin)
        header!(ctx, "Access-Control-Allow-Methods", allowed_methods)
        header!(ctx, "Access-Control-Allow-Headers", headers)
        credentials && header!(ctx, "Access-Control-Allow-Credentials", "true")
        exposed_headers === nothing || header!(ctx, "Access-Control-Expose-Headers", exposed_headers)
        max_age_value === nothing || header!(ctx, "Access-Control-Max-Age", max_age_value)

        if uppercase(ctx.method) == "OPTIONS"
            status!(ctx, 204)
            body!(ctx, "")
            return ctx
        end

        return next()
    end
end
