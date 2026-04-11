"""
    start(app; host = "127.0.0.1", port = 8080, kw...)

Start an HTTP server for `app`.
"""
function start(app::App; host::AbstractString = "127.0.0.1", port::Integer = 8080, max_content_size::Integer = app_config_int(app, "max_content_size", DEFAULT_MAX_CONTENT_SIZE), kw...)
    return serve(req -> dispatch(app, req), host = host, port = port, max_content_size = max_content_size, kw...)
end
