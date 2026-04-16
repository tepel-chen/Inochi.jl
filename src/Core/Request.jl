mutable struct LazyBody
    source::String
    start::Int
    stop::Int
    cache::Union{Nothing,Vector{UInt8}}
end

LazyBody(source::String, start::Int, stop::Int) = LazyBody(source, start, stop, nothing)

"""
    PayloadTooLargeError

Raised when a request body exceeds `max_content_size`.
"""
struct PayloadTooLargeError <: Exception end

Base.showerror(io::IO, ::PayloadTooLargeError) = print(io, "HTTP request body exceeds max_content_size")

"""
    Request

Minimal HTTP request representation.
"""
struct Request
    method::Union{String,SubString{String}}
    target::Union{String,SubString{String}}
    version::Int
    headers::Headers
    body::Union{Vector{UInt8},LazyBody}

    function Request(method::String,
                     target::String,
                     version::Union{Integer,VersionNumber},
                     headers::Headers,
                     body::Union{Vector{UInt8},LazyBody}=UInt8[])
        return new(method, target, _request_version(version), headers, body)
    end

    function Request(method::SubString{String},
                     target::SubString{String},
                     version::Union{Integer,VersionNumber},
                     headers::Headers,
                     body::Union{Vector{UInt8},LazyBody}=UInt8[])
        return new(method, target, _request_version(version), headers, body)
    end
end


_request_version(version::Integer) = Int(version)
_request_version(version::VersionNumber) = Int(version.major)
Request(method::AbstractString, target::AbstractString) =
    Request(method, target, 1, Headers(), UInt8[])

Request(method::AbstractString,
        target::AbstractString,
        headers::Union{AbstractDict{<:AbstractString,<:AbstractString},AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}},
        body::AbstractString) =
    Request(method, target, 1, _normalize_headers(headers), Vector{UInt8}(codeunits(body)))

Request(method::AbstractString,
        target::AbstractString,
        headers::Union{AbstractDict{<:AbstractString,<:AbstractString},AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}}) =
    Request(method, target, 1, _normalize_headers(headers), UInt8[])

Request(method::AbstractString,
        target::AbstractString,
        headers::Union{AbstractDict{<:AbstractString,<:AbstractString},AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}},
        body::AbstractVector{UInt8}) =
    Request(method, target, 1, _normalize_headers(headers), body isa Vector{UInt8} ? body : collect(body))

Request(method::AbstractString,
        target::AbstractString,
        version::Union{Integer,VersionNumber},
        headers::Union{AbstractDict{<:AbstractString,<:AbstractString},AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}},
        body::AbstractString) =
    Request(method, target, version, _normalize_headers(headers), Vector{UInt8}(codeunits(body)))

Request(method::AbstractString,
        target::AbstractString,
        version::Union{Integer,VersionNumber},
        headers::Union{AbstractDict{<:AbstractString,<:AbstractString},AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}},
        body::AbstractVector{UInt8}) =
    Request(method, target, version, _normalize_headers(headers), body isa Vector{UInt8} ? body : collect(body))

"""
    bodybytes(request_or_body)

Return the request body as bytes, materializing lazy bodies only when needed.
"""
function bodybytes(body::Vector{UInt8})
    return body
end

function bodybytes(body::LazyBody)
    cached = body.cache
    cached !== nothing && return cached
    len = body.stop - body.start + 1
    if len <= 0
        body.cache = UInt8[]
        return body.cache
    end
    bytes = Vector{UInt8}(codeunits(body.source[body.start:body.stop]))
    body.cache = bytes
    return bytes
end

bodybytes(request::Request) = bodybytes(request.body)

"""
    bodytext(request_or_body)

Return the request body as text, materializing lazy bodies only when needed.
"""
function bodytext(body::Vector{UInt8})
    return String(body)
end

function bodytext(body::LazyBody)
    body.stop < body.start && return ""
    return body.source[body.start:body.stop]
end

bodytext(request::Request) = bodytext(request.body)

"""
    bodylength(request_or_body)

Return the request body length without forcing unnecessary materialization.
"""
function bodylength(body::Vector{UInt8})
    return length(body)
end

function bodylength(body::LazyBody)
    return max(0, body.stop - body.start + 1)
end

bodylength(request::Request) = bodylength(request.body)

mutable struct _QueuedRequest
    request::Request
    keep_alive::Bool
end

mutable struct _RequestState
    request_bytes::Vector{UInt8}
    method_start::Int
    method_stop::Int
    target_start::Int
    target_stop::Int
    header_ranges::Vector{NTuple{4,Int}}
    body_start::Int
    body_stop::Int
    current_field_start::Int
    current_value_start::Int
    headers::Headers
    completed::Vector{_QueuedRequest}
    http_major::Int
    http_minor::Int
    max_content_size::Int
    body_too_large::Bool
end

_RequestState(max_content_size::Integer = typemax(Int)) =
    _RequestState(UInt8[], 0, 0, 0, 0, NTuple{4,Int}[], 0, 0, 0, 0, Headers(), _QueuedRequest[], 1, 1, Int(max_content_size), false)

_parse_error(parser::LlhttpWrapper.Parser, code) = begin
    reason = LlhttpWrapper.get_error_reason(parser)
    parts = String[]
    push!(parts, LlhttpWrapper.errno_name(code))
    reason !== nothing && !isempty(reason) && push!(parts, reason)
    ErrorException("HTTP parse error ($(join(parts, ", ")))")
end

_state_ref(parser::Ptr{LlhttpWrapper.llhttp_t}) = begin
    ptr = LlhttpWrapper.userdata(parser)
    ptr == C_NULL && return nothing
    unsafe_pointer_to_objref(Ptr{Nothing}(ptr))::Base.RefValue{_RequestState}
end

_state(parser::Ptr{LlhttpWrapper.llhttp_t}) = begin
    state_ref = _state_ref(parser)
    state_ref === nothing && return nothing
    state_ref[]
end

function _append_fragment!(buffer::Vector{UInt8}, at::Ptr{UInt8}, len::Csize_t)
    len == 0 && return buffer
    oldlen = length(buffer)
    resize!(buffer, oldlen + Int(len))
    unsafe_copyto!(pointer(buffer, oldlen + 1), at, Int(len))
    return buffer
end

function _reset!(state::_RequestState)
    empty!(state.request_bytes)
    state.method_start = 0
    state.method_stop = 0
    state.target_start = 0
    state.target_stop = 0
    empty!(state.header_ranges)
    state.body_start = 0
    state.body_stop = 0
    state.current_field_start = 0
    state.current_value_start = 0
    empty!(state.headers)
    state.http_major = 1
    state.http_minor = 1
    state.body_too_large = false
    return state
end

@inline function _ascii_case_equal(bytes::Vector{UInt8}, first::Int, last::Int, name::AbstractString)::Bool
    length(name) == last - first + 1 || return false
    @inbounds for (offset, expected) in enumerate(codeunits(name))
        actual = bytes[first + offset - 1]
        actual == expected && continue
        if 0x41 <= actual <= 0x5a
            actual += 0x20
        end
        if 0x41 <= expected <= 0x5a
            expected += 0x20
        end
        actual == expected || return false
    end
    return true
end

function _header_value_range(state::_RequestState, name::AbstractString)
    for (field_start, field_stop, value_start, value_stop) in state.header_ranges
        _ascii_case_equal(state.request_bytes, field_start, field_stop, name) && return (value_start, value_stop)
    end
    return nothing
end

function _parse_uint(bytes::Vector{UInt8}, first::Int, last::Int)
    first > last && return nothing
    value = 0
    @inbounds for index in first:last
        byte = bytes[index]
        0x30 <= byte <= 0x39 || return nothing
        digit = Int(byte - 0x30)
        value > (typemax(Int) - digit) ÷ 10 && return typemax(Int)
        value = value * 10 + digit
    end
    return value
end

function _content_length(state::_RequestState)
    value_range = _header_value_range(state, "Content-Length")
    value_range === nothing && return nothing
    first, last = value_range
    while first <= last && state.request_bytes[first] <= 0x20
        first += 1
    end
    while first <= last && state.request_bytes[last] <= 0x20
        last -= 1
    end
    return _parse_uint(state.request_bytes, first, last)
end

@inline function _pause_body_too_large!(parser::Ptr{LlhttpWrapper.llhttp_t}, state::_RequestState)
    state.body_too_large = true
    LlhttpWrapper.pause!(parser)
    return LlhttpWrapper.HPE_PAUSED
end

function _on_message_begin(parser::Ptr{LlhttpWrapper.llhttp_t})
    state = _state(parser)
    state === nothing && return Cint(0)
    _reset!(state)
    return Cint(0)
end

function _on_method(parser::Ptr{LlhttpWrapper.llhttp_t}, at::Ptr{UInt8}, len::Csize_t)
    state = _state(parser)
    state === nothing && return Cint(0)
    state.method_start == 0 && (state.method_start = length(state.request_bytes) + 1)
    _append_fragment!(state.request_bytes, at, len)
    state.method_stop = length(state.request_bytes)
    return Cint(0)
end

_on_method_complete(parser::Ptr{LlhttpWrapper.llhttp_t}) = Cint(0)

function _on_url(parser::Ptr{LlhttpWrapper.llhttp_t}, at::Ptr{UInt8}, len::Csize_t)
    state = _state(parser)
    state === nothing && return Cint(0)
    state.target_start == 0 && (state.target_start = length(state.request_bytes) + 1)
    _append_fragment!(state.request_bytes, at, len)
    state.target_stop = length(state.request_bytes)
    return Cint(0)
end

_on_url_complete(parser::Ptr{LlhttpWrapper.llhttp_t}) = Cint(0)

function _on_header_field(parser::Ptr{LlhttpWrapper.llhttp_t}, at::Ptr{UInt8}, len::Csize_t)
    state = _state(parser)
    state === nothing && return Cint(0)
    state.current_field_start == 0 && (state.current_field_start = length(state.request_bytes) + 1)
    _append_fragment!(state.request_bytes, at, len)
    return Cint(0)
end

_on_header_field_complete(parser::Ptr{LlhttpWrapper.llhttp_t}) = Cint(0)

function _on_header_value(parser::Ptr{LlhttpWrapper.llhttp_t}, at::Ptr{UInt8}, len::Csize_t)
    state = _state(parser)
    state === nothing && return Cint(0)
    state.current_value_start == 0 && (state.current_value_start = length(state.request_bytes) + 1)
    _append_fragment!(state.request_bytes, at, len)
    return Cint(0)
end

function _on_header_value_complete(parser::Ptr{LlhttpWrapper.llhttp_t})
    state = _state(parser)
    state === nothing && return Cint(0)
    state.current_field_start == 0 && return Cint(0)
    field_stop = state.current_value_start == 0 ? length(state.request_bytes) : state.current_value_start - 1
    value_start = state.current_value_start
    value_stop = length(state.request_bytes)
    push!(state.header_ranges, (state.current_field_start, field_stop, value_start, value_stop))
    state.current_field_start = 0
    state.current_value_start = 0
    return Cint(0)
end

function _on_headers_complete(parser::Ptr{LlhttpWrapper.llhttp_t})
    state = _state(parser)
    state === nothing && return Cint(0)
    state.http_major = Int(LlhttpWrapper.get_http_major(parser))
    state.http_minor = Int(LlhttpWrapper.get_http_minor(parser))
    content_length = _content_length(state)
    content_length !== nothing && content_length > state.max_content_size && return _pause_body_too_large!(parser, state)
    return Cint(0)
end

function _on_body(parser::Ptr{LlhttpWrapper.llhttp_t}, at::Ptr{UInt8}, len::Csize_t)
    state = _state(parser)
    state === nothing && return Cint(0)
    current_body_length = state.body_start == 0 ? 0 : state.body_stop - state.body_start + 1
    current_body_length + Int(len) > state.max_content_size && return _pause_body_too_large!(parser, state)
    state.body_start == 0 && (state.body_start = length(state.request_bytes) + 1)
    _append_fragment!(state.request_bytes, at, len)
    state.body_stop = length(state.request_bytes)
    return Cint(0)
end

function _on_message_complete(parser::Ptr{LlhttpWrapper.llhttp_t})
    state = _state(parser)
    state === nothing && return Cint(0)
    request_bytes = state.request_bytes
    method = String(request_bytes[state.method_start:state.method_stop])
    target = String(request_bytes[state.target_start:state.target_stop])
    request_string = String(request_bytes)
    headers = Headers(request_string, state.header_ranges)
    body = state.body_start == 0 ? LazyBody(request_string, 1, 0) : LazyBody(request_string, state.body_start, state.body_stop)
    state.headers = Headers()
    state.request_bytes = UInt8[]
    state.header_ranges = HeaderRange[]
    push!(state.completed, _QueuedRequest(Request(
        method,
        target,
        state.http_major,
        headers,
        body,
    ), LlhttpWrapper.should_keep_alive(parser)))
    return Cint(0)
end

_on_reset(parser::Ptr{LlhttpWrapper.llhttp_t}) = begin
    state = _state(parser)
    state === nothing && return Cint(0)
    _reset!(state)
    Cint(0)
end

function _parser_settings()
    return LlhttpWrapper.llhttp_settings_t(
        @cfunction(_on_message_begin, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        C_NULL,
        @cfunction(_on_url, Cint, (Ptr{LlhttpWrapper.llhttp_t}, Ptr{UInt8}, Csize_t)),
        C_NULL,
        @cfunction(_on_method, Cint, (Ptr{LlhttpWrapper.llhttp_t}, Ptr{UInt8}, Csize_t)),
        C_NULL,
        @cfunction(_on_header_field, Cint, (Ptr{LlhttpWrapper.llhttp_t}, Ptr{UInt8}, Csize_t)),
        @cfunction(_on_header_value, Cint, (Ptr{LlhttpWrapper.llhttp_t}, Ptr{UInt8}, Csize_t)),
        C_NULL,
        C_NULL,
        @cfunction(_on_headers_complete, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        @cfunction(_on_body, Cint, (Ptr{LlhttpWrapper.llhttp_t}, Ptr{UInt8}, Csize_t)),
        @cfunction(_on_message_complete, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        C_NULL,
        @cfunction(_on_url_complete, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        C_NULL,
        @cfunction(_on_method_complete, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        C_NULL,
        @cfunction(_on_header_field_complete, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        @cfunction(_on_header_value_complete, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
        C_NULL,
        C_NULL,
        C_NULL,
        C_NULL,
        @cfunction(_on_reset, Cint, (Ptr{LlhttpWrapper.llhttp_t},)),
    )
end

function _read_chunk(io::OpenSSL.SSLStream)
    while true
        chunk = try
            readavailable(io)
        catch err
            err isa EOFError ? UInt8[] : rethrow(err)
        end
        isempty(chunk) || return chunk
        isopen(io) || return UInt8[]
        eof(io) && return UInt8[]
        yield()
    end
end

function _read_chunk(io::IO)
    while true
        chunk = try
            readavailable(io)
        catch err
            err isa EOFError ? UInt8[] : rethrow(err)
        end
        isempty(chunk) || return chunk
        isopen(io) || return UInt8[]
        buf = Vector{UInt8}(undef, 1)
        n = try
            readbytes!(io, buf, 1)
        catch err
            err isa EOFError ? 0 : rethrow(err)
        end
        n > 0 && return resize!(buf, n)
        eof(io) && return UInt8[]
        yield()
    end
end

function _next_completed_request(state::_RequestState)
    isempty(state.completed) && return nothing
    return popfirst!(state.completed)
end

function _next_request!(io::IO, parser::LlhttpWrapper.Parser, state_ref::Base.RefValue{_RequestState}, prefetched = nothing)
    while true
        request = _next_completed_request(state_ref[])
        request !== nothing && return request

        chunk = prefetched === nothing ? _read_chunk(io) : _read_chunk(io, prefetched)
        isempty(chunk) && return nothing
        code = LlhttpWrapper.execute!(parser, chunk)
        code == LlhttpWrapper.HPE_OK || code == LlhttpWrapper.HPE_PAUSED || code == LlhttpWrapper.HPE_PAUSED_UPGRADE || throw(_parse_error(parser, code))
        state_ref[].body_too_large && throw(PayloadTooLargeError())
    end
end

function _read_request(io::IO; max_content_size::Integer = typemax(Int))
    state_ref = Ref(_RequestState(max_content_size))
    parser = LlhttpWrapper.Parser(LlhttpWrapper.HTTP_REQUEST; settings=_parser_settings())
    LlhttpWrapper.set_userdata!(parser, Base.pointer_from_objref(state_ref))
    GC.@preserve state_ref parser begin
        request = _next_request!(io, parser, state_ref)
        request === nothing && throw(EOFError("incomplete HTTP request"))
        return request.request
    end
end
