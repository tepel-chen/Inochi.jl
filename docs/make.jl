using Documenter
using Inochi

makedocs(;
    sitename = "Inochi.jl",
    modules = [Inochi],
    format = Documenter.HTML(; prettyurls = false),
    pages = [
        "Home" => "index.md",
        "Guides" => [
            "Routing and Middleware" => "guides/routing.md",
            "Context and Responses" => "guides/context.md",
            "Static Files" => "guides/static-files.md",
        ],
        "Examples" => [
            "Todo App" => "examples/todo.md",
        ],
        "API" => "api.md",
    ],
)
