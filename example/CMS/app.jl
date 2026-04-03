import Pkg

Pkg.activate(@__DIR__; io = devnull)
if get(ENV, "CMS_SKIP_PKG_SETUP", "0") != "1"
    include(joinpath(@__DIR__, "bootstrap.jl"))
    bootstrap(; do_precompile = false)
end

using Inochi
using IwaiEngine

include(joinpath(@__DIR__, "store.jl"))
include(joinpath(@__DIR__, "views.jl"))
include(joinpath(@__DIR__, "security.jl"))
include(joinpath(@__DIR__, "auth.jl"))
include(joinpath(@__DIR__, "posts.jl"))
include(joinpath(@__DIR__, "admin.jl"))

const STORE = build_seed_store()
const app = App()
const posts_app = build_posts_app(STORE)
const admin_app = build_admin_app(STORE)

app.config["secret"] = "cms-example-secret"
app.renderer = (template, data) -> IwaiEngine.parse(template)(data)
app.views = joinpath(@__DIR__, "views")
app.file_renderer = (filepath, data) -> IwaiEngine.load(filepath; root = app.views)(data)

use(app, logger())
use(app, csp_middleware())
use(app, csrf())
use(app, attach_current_user(STORE))

get(app, "/static/*", static(joinpath(@__DIR__, "public")))
register_auth_routes!(app, STORE)
route(app, "/post", posts_app)
route(app, "/admin", admin_app)

get(app, "/") do ctx
    ctx.render("pages/index.iwai", home_view(STORE, ctx))
end

const HOST = get(ENV, "HOST", "127.0.0.1")
const PORT = Base.parse(Int, get(ENV, "PORT", "8080"))

println("CMS example listening on http://$(HOST):$(PORT)")

wait(start(app; host = HOST, port = PORT))
