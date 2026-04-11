const UTF8_MIME_TYPES = Set((
    "application/json",
    "application/xml",
    "image/svg+xml",
    "text/css",
    "text/csv",
    "text/html",
    "text/javascript",
    "text/plain",
))

const ETAG_HEADER_NAME = "ETag"
const IF_NONE_MATCH_HEADER_NAME = "If-None-Match"

function executable_root()::String
    base = isempty(Base.PROGRAM_FILE) ? pwd() : dirname(abspath(Base.PROGRAM_FILE))
    return normpath(base)
end

function path_within_root(path::AbstractString, root::AbstractString)::Bool
    normalized_path = normpath(path)
    normalized_root = normpath(root)
    relative = relpath(normalized_path, normalized_root)
    return relative != ".." && !startswith(relative, ".." * Base.Filesystem.path_separator)
end

function safe_join(root::AbstractString, path::AbstractString)
    normalized_root = normpath(abspath(root))
    candidate = isabspath(path) ? normpath(path) : normpath(joinpath(normalized_root, path))
    return path_within_root(candidate, normalized_root) ? candidate : nothing
end

function content_type_for_path(path::AbstractString)::String
    mime = string(mime_from_path(path))
    return mime in UTF8_MIME_TYPES || startswith(mime, "text/") ? mime * "; charset=utf-8" : mime
end

function etag_for_bytes(bytes::Vector{UInt8})::String
    return "\"" * bytes2hex(sha1(bytes)) * "\""
end

function etag_for_file(path::AbstractString)::String
    info = stat(path)
    size_hex = string(info.size; base = 16)
    mtime_ns = round(Int, info.mtime * 1_000_000_000)
    mtime_hex = string(mtime_ns; base = 16)
    return "\"" * size_hex * "-" * mtime_hex * "\""
end

response_bytes(body::Vector{UInt8}) = body
response_bytes(body::AbstractVector{UInt8}) = Vector{UInt8}(body)
response_bytes(body::AbstractString) = Vector{UInt8}(codeunits(body))
response_bytes(body) = throw(ArgumentError("Unsupported response body type: $(typeof(body))"))

function if_none_match_matches(req::Request, etag::AbstractString)::Bool
    header = strip(get(req.headers, IF_NONE_MATCH_HEADER_NAME, ""))
    isempty(header) && return false
    header == "*" && return true

    for candidate in split(header, ',')
        strip(candidate) == etag && return true
    end

    return false
end

function maybe_not_modified(req::Union{Nothing,Request}, etag::AbstractString)::Union{Nothing,Response}
    req === nothing && return nothing
    if if_none_match_matches(req, etag)
        return Response(304, [ETAG_HEADER_NAME => etag])
    end
    return nothing
end

function file_response(path::AbstractString; req::Union{Nothing,Request} = nothing, root::AbstractString = executable_root())::Response
    resolved = safe_join(root, path)
    resolved === nothing && return Response(403, "Forbidden")
    isfile(resolved) || return Response(404, "Not Found")

    etag = etag_for_file(resolved)
    not_modified = maybe_not_modified(req, etag)
    not_modified !== nothing && return not_modified

    body = read(resolved)
    headers = ["Content-Type" => content_type_for_path(resolved), ETAG_HEADER_NAME => etag]
    return Response(200, headers, body)
end

"""
    sendFile(path; root = executable_root())

Return a file response rooted at `root`. Requests outside the root are rejected.
"""
function sendFile(path::AbstractString; root::AbstractString = executable_root())::Response
    return file_response(path; root = root)
end

"""
    sendFile(ctx, path; root = executable_root())

Return a file response rooted at `root`, with `If-None-Match` support from `ctx.req`.
"""
function sendFile(ctx::Context, path::AbstractString; root::AbstractString = executable_root())::Response
    return file_response(path; req = ctx.req, root = root)
end

"""
    static(root)

Create a handler for serving files rooted at `root`, typically mounted on a wildcard route.
"""
function static(root::AbstractString)::Function
    normalized_root = normpath(abspath(root))

    return function (ctx::Context)
        relative_path = get(ctx.params, "*", "")
        decoded_path = HTTP.URIs.unescapeuri(relative_path)
        return file_response(decoded_path; req = ctx.req, root = normalized_root)
    end
end
