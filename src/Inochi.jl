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

RuntimeGeneratedFunctions.init(@__MODULE__)

include("Core.jl")

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
include("middleware/middleware.jl")
include("server.jl")

end
