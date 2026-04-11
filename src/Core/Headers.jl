const HeaderRange = NTuple{4,Int}

"""
    Headers

HTTP headers container used by `Request` and `Response`.
It supports zero-copy parsing from a source string and
case-insensitive lookup.
"""
mutable struct Headers <: AbstractDict{String,String}
    source::Union{Nothing,String}
    ranges::Vector{HeaderRange}
    data::Vector{Pair{String,String}}
end

Headers() = Headers(nothing, HeaderRange[], Pair{String,String}[])

Headers(source::String, ranges::Vector{HeaderRange}) =
    Headers(source, ranges, Pair{String,String}[])

Headers(data::Vector{Pair{String,String}}) =
    Headers(nothing, HeaderRange[], data)

Headers(data::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}) =
    Headers(nothing, HeaderRange[], [String(name) => String(value) for (name, value) in data])

Base.length(headers::Headers) = headers.source === nothing ? length(headers.data) : length(headers.ranges)

function Base.iterate(headers::Headers, state::Int = 1)
    if headers.source === nothing
        return iterate(headers.data, state)
    end
    state > length(headers.ranges) && return nothing
    source = headers.source::String
    field_start, field_stop, value_start, value_stop = headers.ranges[state]
    pair = SubString(source, field_start, field_stop) => SubString(source, value_start, value_stop)
    return pair, state + 1
end

function Base.empty!(headers::Headers)
    empty!(headers.data)
    empty!(headers.ranges)
    headers.source = nothing
    return headers
end

function Base.copy(headers::Headers)
    return Headers(
        headers.source === nothing ? nothing : headers.source,
        copy(headers.ranges),
        copy(headers.data),
    )
end

Base.keys(headers::Headers) = (first(pair) for pair in headers)
Base.pairs(headers::Headers) = headers

function _header_lookup_key(headers::Headers, name::AbstractString)
    if headers.source === nothing
        for (index, (header, _)) in enumerate(headers.data)
            _ascii_case_equal(header, name) && return index
        end
    else
        source = headers.source::String
        for (index, (field_start, field_stop, _, _)) in enumerate(headers.ranges)
            _ascii_case_equal(SubString(source, field_start, field_stop), name) && return index
        end
    end
    return nothing
end

function Base.haskey(headers::Headers, name::AbstractString)
    _header_lookup_key(headers, name) !== nothing
end

function Base.getindex(headers::Headers, name::AbstractString)
    key = _header_lookup_key(headers, name)
    key === nothing && throw(KeyError(name))
    if headers.source === nothing
        return headers.data[key].second
    end
    source = headers.source::String
    _, _, value_start, value_stop = headers.ranges[key]
    return SubString(source, value_start, value_stop)
end

function Base.get(headers::Headers, name::AbstractString, default)
    key = _header_lookup_key(headers, name)
    key === nothing && return default
    if headers.source === nothing
        return headers.data[key].second
    end
    source = headers.source::String
    _, _, value_start, value_stop = headers.ranges[key]
    return SubString(source, value_start, value_stop)
end

"""
    getheaders(headers, name)

Return all header values matching `name` from a `Headers` collection.
The lookup is case-insensitive and preserves the stored order.
"""
function getheaders(headers::Headers, name::AbstractString)
    values = String[]
    for (header, value) in headers
        _ascii_case_equal(header, name) || continue
        push!(values, value isa String ? value : String(value))
    end
    return values
end

"""
    appendheader!(headers, pair)

Append a header pair to `headers` without removing existing values.
This is intended for multi-valued response headers such as `Set-Cookie`.
"""
function appendheader!(headers::Headers, pair::Pair{<:AbstractString,<:AbstractString})
    push!(headers.data, first(pair) => last(pair))
    return headers
end

function Base.setindex!(headers::Headers, value::AbstractString, name::AbstractString)
    if headers.source !== nothing
        _materialize_headers!(headers)
    end
    data_index = nothing
    for (index, (header, _)) in enumerate(headers.data)
        _ascii_case_equal(header, name) && (data_index = index; break)
    end
    if data_index === nothing
        push!(headers.data, name => value)
    else
        headers.data[data_index] = name => value
    end
    return headers
end

function Base.delete!(headers::Headers, name::AbstractString)
    if headers.source !== nothing
        _materialize_headers!(headers)
    end
    data_index = nothing
    for (index, (header, _)) in enumerate(headers.data)
        _ascii_case_equal(header, name) && (data_index = index; break)
    end
    data_index === nothing && return headers
    deleteat!(headers.data, data_index)
    return headers
end

function _materialize_headers!(headers::Headers)
    headers.source === nothing && return headers
    source = headers.source::String
    for (field_start, field_stop, value_start, value_stop) in headers.ranges
        push!(headers.data, String(source[field_start:field_stop]) => String(source[value_start:value_stop]))
    end
    empty!(headers.ranges)
    headers.source = nothing
    return headers
end

function _normalize_headers(headers)
    return Headers([String(name) => String(value) for (name, value) in headers])
end

function _is_tchar_byte(byte::UInt8)
    return (0x30 <= byte <= 0x39) ||
           (0x41 <= byte <= 0x5a) ||
           (0x61 <= byte <= 0x7a) ||
           byte == UInt8('!') ||
           byte == UInt8('#') ||
           byte == UInt8('$') ||
           byte == UInt8('%') ||
           byte == UInt8('&') ||
           byte == UInt8('\'') ||
           byte == UInt8('*') ||
           byte == UInt8('+') ||
           byte == UInt8('-') ||
           byte == UInt8('.') ||
           byte == UInt8('^') ||
           byte == UInt8('_') ||
           byte == UInt8('`') ||
           byte == UInt8('|') ||
           byte == UInt8('~')
end

function _validate_header_name(name::AbstractString)
    isempty(name) && throw(ArgumentError("header name must not be empty"))
    for byte in codeunits(name)
        _is_tchar_byte(byte) || throw(ArgumentError("header name is not RFC-compliant"))
    end
    return name
end

function _validate_header_value(value::AbstractString)
    for byte in codeunits(value)
        byte == 0x09 && continue
        byte == 0x20 && continue
        (0x21 <= byte <= 0x7e) && continue
        (0x80 <= byte <= 0xff) && continue
        throw(ArgumentError("header value is not RFC-compliant"))
    end
    return value
end

function _validate_header!(name::AbstractString, value::AbstractString)
    _validate_header_name(name)
    _validate_header_value(value)
    return nothing
end

@noinline function _ascii_case_equal(a::AbstractString, b::AbstractString)
    length(a) == length(b) || return false
    for (ca, cb) in zip(codeunits(a), codeunits(b))
        if ca == cb
            continue
        end
        if 0x41 <= ca <= 0x5a
            ca += 0x20
        end
        if 0x41 <= cb <= 0x5a
            cb += 0x20
        end
        ca == cb || return false
    end
    return true
end
