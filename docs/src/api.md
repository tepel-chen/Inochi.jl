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
```

## Routing

```@docs
use
route
get
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
set!
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
