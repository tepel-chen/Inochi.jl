"""
Route parameter storage used by matched handlers and middleware.
"""
const RouteParams = Dict{String,String}
const AppConfig = Dict{String,Union{String,Int}}
const DEFAULT_MAX_CONTENT_SIZE = 4 * 1024 * 1024

struct RouteDefinition
    method::String
    path::String
    handler::Function
    is_middleware::Bool
end

struct DynamicRoute
    handler::Function
    path::String
    segments::Vector{String}
    param_names::Vector{String}
    is_middleware::Bool
end

mutable struct RouteTrieNode
    static_children::Vector{Pair{String,RouteTrieNode}}
    param_child::Union{Nothing,RouteTrieNode}
    terminal_routes::Vector{DynamicRoute}
    wildcard_routes::Vector{DynamicRoute}
end

RouteTrieNode() = RouteTrieNode(Pair{String,RouteTrieNode}[], nothing, DynamicRoute[], DynamicRoute[])

struct StaticRoute
    handler::Function
    path::String
    is_middleware::Bool
end

struct MatchedRoute
    handler::Function
    path::String
    params::RouteParams
end

struct MethodMatcher
    dynamic_matcher::Function
    static_map::Dict{String,StaticRoute}
end

mutable struct App
    routes::Vector{RouteDefinition}
    matchers::Dict{String,MethodMatcher}
    dirty::Bool
    error_handler::Union{Nothing,Function}
    notfound_handler::Union{Nothing,Function}
    config::AppConfig
    renderer::Union{Nothing,Function}
    file_renderer::Union{Nothing,Function}
    views::Union{Nothing,String}
end

"""
    App()

Create a new Inochi application.
"""
App() = App(
    RouteDefinition[],
    Dict{String,MethodMatcher}(),
    true,
    nothing,
    nothing,
    AppConfig("max_content_size" => DEFAULT_MAX_CONTENT_SIZE),
    nothing,
    nothing,
    nothing,
)
