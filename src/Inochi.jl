module Inochi

import Base: get

using HTTP
using JSON
using MIMEs
using Base64
using SHA
using Dates
using Printf
using Random
using RuntimeGeneratedFunctions
using OpenSSL

RuntimeGeneratedFunctions.init(@__MODULE__)

module Core

using Sockets
using LlhttpWrapper
using NghttpWrapper
using OpenSSL

include("Core/Headers.jl")
include("Core/Request.jl")
include("Core/Response.jl")
include("Core/HTTP2.jl")

export Request, Response, Headers, PayloadTooLargeError, bodybytes, bodylength, bodytext, getheaders, appendheader!, serve
export LlhttpWrapper, LazyBody, _RequestState, _parser_settings, _next_completed_request, _header_value_range, _content_length, _read_chunk, _normalize_host, _default_error_response, _ascii_case_equal, _write_response

end

using .Core: Request, Response, Headers, PayloadTooLargeError, bodybytes, bodylength, bodytext, getheaders, appendheader!, serve

const INOCHI_VERSION = string(pkgversion(@__MODULE__))
const JULIA_VERSION = string(VERSION)

export App, RouteParams, connect, delete, get, head, options, patch, post, put, trace, use, start
export Request, Response, Headers, PayloadTooLargeError, bodybytes, bodylength, bodytext, getheaders, appendheader!, serve
export Core
export Context, basicAuth, body!, cookie, cors, csrf, csrf_token, etag, header!, html, logger, next, on_error, on_notfound, redirect, render, render_text, reqfile, reqform, reqjson, reqmultipart, reqquery, reqtext, response!, route, secure_cookie, sendFile, set_secure_cookie, setcookie, start, static, status!, text, json, set!, get

include("types.jl")
include("context.jl")
include("files.jl")
include("routing.jl")
include("middleware/cors.jl")
include("middleware/csrf.jl")
include("middleware/etag.jl")
include("middleware/logger.jl")
include("middleware/basic_auth.jl")

"""
    start(app; host = "127.0.0.1", port = 8080, max_threads = Threads.nthreads(), kw...)

Start an HTTP server for `app`.

All keyword arguments are forwarded to [`serve`](@ref), including TLS
configuration via an `OpenSSL.SSLContext` loaded with a server certificate and key.
`max_threads` limits how many connection handlers may run concurrently.
"""
function start(app::App; host::AbstractString = "127.0.0.1", port::Integer = 8080, max_content_size::Integer = app_config_int(app, "max_content_size", DEFAULT_MAX_CONTENT_SIZE), max_threads::Integer = Threads.nthreads(), kw...)
    return serve(req -> dispatch(app, req), host = host, port = port, max_content_size = max_content_size, max_threads = max_threads; kw...)
end

end
