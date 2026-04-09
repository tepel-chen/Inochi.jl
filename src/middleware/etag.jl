"""
    etag()

Create middleware that adds an `ETag` header for string and byte responses and
returns `304 Not Modified` when `If-None-Match` matches.
"""
function etag()
    return function (ctx::Context)
        next(ctx)
        getfield(ctx, :response) !== nothing && return ctx
        existing = get(ctx.headers, ETAG_HEADER_NAME, "")

        if isempty(existing)
            body_bytes = response_bytes(ctx.body)
            body_bytes === nothing && return ctx
            existing = etag_for_bytes(body_bytes)
            header!(ctx, ETAG_HEADER_NAME, existing)
        end

        if if_none_match_matches(ctx.req, existing)
            status!(ctx, 304)
            body!(ctx, UInt8[])
        end

        return ctx
    end
end
