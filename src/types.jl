"""
Route parameter storage used by matched handlers and middleware.
"""
const RouteParams = Dict{AbstractString,AbstractString}
const EMPTY_ROUTE_PARAMS = Base.ImmutableDict{String,String}()
const ResponseBody = Union{AbstractString,Vector{UInt8}}
const DispatchBacktrace = Vector{Union{Ptr{Nothing},Base.InterpreterIP}}
const AppConfig = Dict{String,Union{String,Int}}
const DEFAULT_MAX_CONTENT_SIZE = 4 * 1024 * 1024

struct RouteDefinition
    method::String
    path::String
    handler::Function
    is_middleware::Bool
end

struct MiddlewareRoute
    handler::Function
    path::String
    prefix::String
    order::Int
end

struct DynamicRoute
    handler::Function
    path::String
    segments::Vector{String}
    param_names::Vector{String}
    is_middleware::Bool
    middleware_routes::Vector{MiddlewareRoute}
end

struct MiddlewareParams
    tail::SubString{String}
end

struct RouteParamsView{N}
    names::NTuple{N,String}
    values::NTuple{N,SubString{String}}
end

struct MiddlewareMatch
    handler::Function
    path::String
    params::MiddlewareParams
    order::Int
end

const EMPTY_MIDDLEWARE_MATCHES = MiddlewareMatch[]

mutable struct RouteTrieNode
    static_children::Vector{Pair{String,RouteTrieNode}}
    param_child::Union{Nothing,RouteTrieNode}
    terminal_routes::Vector{DynamicRoute}
    wildcard_routes::Vector{DynamicRoute}
end

RouteTrieNode() = RouteTrieNode(Pair{String,RouteTrieNode}[], nothing, DynamicRoute[], DynamicRoute[])

mutable struct MiddlewareTrieNode
    static_children::Vector{Pair{String,MiddlewareTrieNode}}
    terminal_routes::Vector{MiddlewareRoute}
    ordered_routes::Vector{MiddlewareRoute}
end

MiddlewareTrieNode() = MiddlewareTrieNode(Pair{String,MiddlewareTrieNode}[], MiddlewareRoute[], MiddlewareRoute[])

const EMPTY_MIDDLEWARE_ROUTES = MiddlewareRoute[]

struct StaticRoute
    handler::Function
    path::String
    is_middleware::Bool
    middleware_routes::Vector{MiddlewareRoute}
end

struct MatchedRoute
    handler::Function
    path::String
    params::RouteParamsView
    middleware_routes::Vector{MiddlewareRoute}
end

struct MethodMatcher
    dynamic_matcher::Function
    static_map::Dict{String,StaticRoute}
end

struct MiddlewareMatcher
    global_routes::Vector{MiddlewareRoute}
    route_count::Int
    middleware_matcher::Function
end

mutable struct App
    routes::Vector{RouteDefinition}
    matchers::Dict{String,MethodMatcher}
    middleware_matchers::Dict{String,MiddlewareMatcher}
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
    Dict{String,MiddlewareMatcher}(),
    true,
    nothing,
    nothing,
    AppConfig("max_content_size" => DEFAULT_MAX_CONTENT_SIZE),
    nothing,
    nothing,
    nothing,
)
