"""
    etag()

Create middleware that adds an `ETag` header for string and byte responses and
returns `304 Not Modified` when `If-None-Match` matches.
"""
function etag()
    return function (ctx::Context)
        response = ctx.next()
        existing = HTTP.header(response, ETAG_HEADER_NAME, "")

        if isempty(existing)
            body_bytes = response_bytes(response.body)
            body_bytes === nothing && return response
            existing = etag_for_bytes(body_bytes)
            with_etag(response, existing)
        end

        if if_none_match_matches(ctx.req, existing)
            not_modified = HTTP.Response(304, Vector{Pair{String,String}}(), UInt8[])
            with_etag(not_modified, existing)
            return not_modified
        end

        return response
    end
end
