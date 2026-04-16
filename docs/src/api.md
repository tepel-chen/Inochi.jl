# API Reference

```@meta
CurrentModule = Inochi
```

## Core

```@docs
App
Context
RouteParams
start
Request
Response
Headers
PayloadTooLargeError
bodybytes
bodylength
bodytext
getheaders
appendheader!
serve
```

## Routing

```@docs
use
route
Inochi.get
post
put
patch
delete
options
head
connect
trace
```

## Request and Response Helpers

```@docs
status!
header!
body!
response!
cookie
text
html
json
redirect
render
render_text
reqtext
reqjson
reqform
reqquery
reqmultipart
reqfile
setcookie
secure_cookie
set_secure_cookie
next
set!
Base.get(ctx::Context, key::AbstractString, default = nothing)
Base.get(ctx::Context, key::Symbol, default = nothing)
```

## File Helpers

```@docs
static
sendFile
```

## Middleware

```@docs
cors
logger
basicAuth
csrf
etag
on_error
on_notfound
```

## TLS

TLS uses `OpenSSL`. Create an `OpenSSL.SSLContext` with a server certificate
and private key, then pass it as `sslconfig` to `serve` or `start`.
