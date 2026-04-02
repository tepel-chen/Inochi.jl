import Pkg

Pkg.activate(normpath(joinpath(@__DIR__, "..", "..")); io = devnull)
Pkg.instantiate(; io = devnull)

using HTTP
using Inochi

include(joinpath(@__DIR__, "store.jl"))
include(joinpath(@__DIR__, "views.jl"))

const STORE = TodoStore()
const app = App()

get(static(joinpath(@__DIR__, "public")), app, "/static/*")

get(app, "/") do ctx
    html(ctx, render_index(STORE))
end

get(app, "/about") do
    sendFile("public/about.html")
end

post(app, "/todos") do ctx
    form = ctx.reqform()
    title = strip(get(form, "title", ""))

    if !isempty(title)
        create_todo!(STORE, title)
    end

    return redirect(ctx, "/")
end

post(app, "/todos/:id/toggle") do ctx
    todo_id = tryparse(Int, ctx.params["id"])
    todo_id !== nothing && toggle_todo!(STORE, todo_id)
    return redirect(ctx, "/")
end

post(app, "/todos/:id/delete") do ctx
    todo_id = tryparse(Int, ctx.params["id"])
    todo_id !== nothing && delete_todo!(STORE, todo_id)
    return redirect(ctx, "/")
end

println("Todo app listening on http://127.0.0.1:8080")

wait(start(app; host = "127.0.0.1", port = 8080))
