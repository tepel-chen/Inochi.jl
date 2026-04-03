import Pkg

Pkg.activate(@__DIR__; io = devnull)
Pkg.add([
    Pkg.PackageSpec(url = "https://github.com/tepel-chen/Inochi.jl"),
    Pkg.PackageSpec(url = "https://github.com/tepel-chen/IwaiEngine.jl"),
]; io = devnull)
Pkg.instantiate(; io = devnull)

using HTTP
using Inochi
using IwaiEngine

include(joinpath(@__DIR__, "store.jl"))
include(joinpath(@__DIR__, "todos.jl"))
include(joinpath(@__DIR__, "views.jl"))

const STORE = TodoStore()
const app = App()
const todos_app = build_todos_app(STORE)

app.renderer = (template, data) -> IwaiEngine.parse(template)(data)
app.views = joinpath(@__DIR__, "views")
app.file_renderer = (filepath, data) -> IwaiEngine.load(filepath; root = app.views)(data)

use(app, logger())

get(app, "/static/*", static(joinpath(@__DIR__, "public")))
route(app, "/todos", todos_app)

get(app, "/") do ctx
    ctx.render("index.iwai", render_index_data(STORE))
end

get(app, "/about") do ctx
    sendFile(ctx, "public/about.html")
end

println("Todo app listening on http://127.0.0.1:8080")

wait(start(app; host = "127.0.0.1", port = 8080))
