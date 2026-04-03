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

const INOCHI_VERSION = string(pkgversion(@__MODULE__))
const JULIA_VERSION = string(VERSION)

export App, RouteParams, connect, delete, get, head, options, patch, post, put, trace, use, start
export Context, basicAuth, body!, cors, csrf, csrf_token, etag, header!, html, logger, on_error, on_notfound, redirect, render, render_text, reqform, reqjson, reqquery, reqtext, route, secure_cookie, sendFile, set_secure_cookie, setcookie, start, static, status!, text, json, set!, get

include("types.jl")
include("context.jl")
include("files.jl")
include("routing.jl")
include("middleware/middleware.jl")
include("server.jl")

end
