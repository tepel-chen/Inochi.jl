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

function executable_root()::String
    base = isempty(Base.PROGRAM_FILE) ? pwd() : dirname(abspath(Base.PROGRAM_FILE))
    return normpath(base)
end

function path_within_root(path::AbstractString, root::AbstractString)::Bool
    normalized_path = normpath(String(path))
    normalized_root = normpath(String(root))
    relative = relpath(normalized_path, normalized_root)
    return relative != ".." && !startswith(relative, ".." * Base.Filesystem.path_separator)
end

function safe_join(root::AbstractString, path::AbstractString)
    normalized_root = normpath(abspath(String(root)))
    candidate = isabspath(path) ? normpath(String(path)) : normpath(joinpath(normalized_root, String(path)))
    return path_within_root(candidate, normalized_root) ? candidate : nothing
end

function content_type_for_path(path::AbstractString)::String
    mime = string(mime_from_path(String(path)))
    return mime in UTF8_MIME_TYPES || startswith(mime, "text/") ? mime * "; charset=utf-8" : mime
end

"""
    sendFile(path; root = executable_root())

Return a file response rooted at `root`. Requests outside the root are rejected.
"""
function sendFile(path::AbstractString; root::AbstractString = executable_root())::HTTP.Response
    resolved = safe_join(root, path)
    resolved === nothing && return HTTP.Response(403, "Forbidden")
    isfile(resolved) || return HTTP.Response(404, "Not Found")

    headers = ["Content-Type" => content_type_for_path(resolved)]
    return HTTP.Response(200, headers, read(resolved))
end

"""
    static(root)

Create a handler for serving files rooted at `root`, typically mounted on a wildcard route.
"""
function static(root::AbstractString)::Function
    normalized_root = normpath(abspath(String(root)))

    return function (ctx::Context)
        relative_path = get(ctx.params, "*", "")
        decoded_path = HTTP.URIs.unescapeuri(relative_path)
        return sendFile(decoded_path; root = normalized_root)
    end
end
