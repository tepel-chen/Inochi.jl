module Inochi

import Base: get

using HTTP
using JSON
using MIMEs
using Base64
using SHA

export App, RouteParams, connect, delete, get, head, options, patch, post, put, trace, use, start
export Context, basicAuth, body!, cors, header!, html, logger, on_error, on_notfound, redirect, reqform, reqjson, reqquery, reqtext, secure_cookie, sendFile, set_secure_cookie, setcookie, start, static, status!, text, json, set!, get

include("types.jl")
include("context.jl")
include("files.jl")
include("routing.jl")
include("middleware/middleware.jl")
include("server.jl")

end
