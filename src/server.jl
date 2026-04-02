"""
    start(app; host = "127.0.0.1", port = 8080, kw...)

Start an HTTP server for `app`.
"""
function start(app::App; host::AbstractString = "127.0.0.1", port::Integer = 8080, kw...)
    return HTTP.serve!(req -> dispatch(app, req), host, port; kw...)
end
