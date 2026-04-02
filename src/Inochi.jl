module Inochi

import Base: get

using HTTP
using JSON
using MIMEs

export App, RouteParams, connect, delete, get, head, options, patch, post, put, trace, use, start
export Context, body!, header!, html, redirect, reqform, reqjson, reqquery, reqtext, sendFile, setcookie, start, static, status!, text, json, set!, get

include("types.jl")
include("context.jl")
include("files.jl")
include("routing.jl")
include("server.jl")

end
