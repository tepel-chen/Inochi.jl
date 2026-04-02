import Pkg

Pkg.activate(normpath(joinpath(@__DIR__, "..", "..")); io = devnull)
Pkg.instantiate(; io = devnull)

using HTTP
using Inochi

include(joinpath(@__DIR__, "store.jl"))
include(joinpath(@__DIR__, "todos.jl"))
include(joinpath(@__DIR__, "views.jl"))

const STORE = TodoStore()
const app = App()
const todos_app = build_todos_app(STORE)

use(app, logger())

get(app, "/static/*", static(joinpath(@__DIR__, "public")))
route(app, "/todos", todos_app)

get(app, "/") do ctx
    html(ctx, render_index(STORE))
end

get(app, "/about") do
    sendFile("public/about.html")
end

println("Todo app listening on http://127.0.0.1:8080")

wait(start(app; host = "127.0.0.1", port = 8080))
