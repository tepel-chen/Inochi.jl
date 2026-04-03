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
    prefers_params::Bool
    is_middleware::Bool
    middleware_scope::Symbol
end

struct DynamicRoute
    handler::Function
    path::String
    param_names::Vector{String}
    param_capture_indexes::Vector{Int}
    is_middleware::Bool
    middleware_scope::Symbol
end

struct StaticRoute
    handler::Function
    path::String
    prefers_params::Bool
    is_middleware::Bool
    middleware_scope::Symbol
end

struct MethodMatcher
    regex::Union{Regex,Nothing}
    route_lookup::Dict{Int,DynamicRoute}
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
