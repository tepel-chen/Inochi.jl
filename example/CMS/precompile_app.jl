using Pkg

Pkg.activate(@__DIR__)
using HTTP
using Inochi
using IwaiEngine

include(joinpath(@__DIR__, "store.jl"))
include(joinpath(@__DIR__, "views.jl"))
include(joinpath(@__DIR__, "security.jl"))
include(joinpath(@__DIR__, "auth.jl"))
include(joinpath(@__DIR__, "posts.jl"))
include(joinpath(@__DIR__, "admin.jl"))

store = CMSStore("host=127.0.0.1 port=5432 dbname=precompile user=precompile password=precompile")
app = App()
app.config["secret"] = "cms-example-secret"
app.renderer = (template, data) -> IwaiEngine.parse(template)(data)
app.views = joinpath(@__DIR__, "views")
app.file_renderer = (filepath, data) -> IwaiEngine.load(filepath; root = app.views)(data)

use(app, logger())
use(app, csp_middleware())
use(app, csrf())
use(app, attach_current_user(store))
get(app, "/static/*", static(joinpath(@__DIR__, "public")))
const auth_app = build_auth_app(store)
route(app, "/", auth_app)
route(app, "/post", build_posts_app(store))
route(app, "/admin", build_admin_app(store))
get(app, "/") do ctx
    render(ctx, "pages/index.iwai", home_view(store, ctx))
end
