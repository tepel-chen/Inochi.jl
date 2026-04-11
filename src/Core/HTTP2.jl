mutable struct _PrefetchedBytes
    bytes::Vector{UInt8}
    index::Int
end

_PrefetchedBytes(bytes::AbstractVector{UInt8}) = _PrefetchedBytes(bytes isa Vector{UInt8} ? bytes : collect(bytes), 1)

function _read_chunk(sock::Sockets.TCPSocket, prefetched::_PrefetchedBytes)
    prefetched.index <= length(prefetched.bytes) || return _read_chunk(sock)
    chunk = copy(@view prefetched.bytes[prefetched.index:end])
    prefetched.index = length(prefetched.bytes) + 1
    return chunk
end

function _sniff_protocol(sock::Sockets.TCPSocket; allow_http1::Bool = true, allow_http2::Bool = true)
    allow_http1 || allow_http2 || throw(ArgumentError("allow_http1 and allow_http2 cannot both be false"))
    allow_http1 && !allow_http2 && return (:http1, _PrefetchedBytes(UInt8[]))
    expected = codeunits(NghttpWrapper.NGHTTP2_CLIENT_MAGIC)
    prefetched = UInt8[]
    while length(prefetched) < length(expected)
        chunk = _read_chunk(sock)
        isempty(chunk) && return nothing
        append!(prefetched, chunk)
        matched = min(length(prefetched), length(expected))
        @inbounds for i in 1:matched
            if prefetched[i] != expected[i]
                allow_http1 && return (:http1, _PrefetchedBytes(prefetched))
                return nothing
            end
        end
    end
    return (:http2, _PrefetchedBytes(prefetched))
end

mutable struct _H2StreamState
    method::Union{Nothing,String,SubString{String}}
    target::Union{Nothing,String,SubString{String}}
    headers::Headers
    body::Vector{UInt8}
    headers_complete::Bool
    responded::Bool
    body_too_large::Bool
    response::Union{Nothing,Response}
    response_provider::Union{Nothing,Base.RefValue{NghttpWrapper.nghttp2_data_provider2}}
    response_offset::Int
end

mutable struct _H2ConnState
    handler::Function
    max_content_size::Int
    streams::Dict{Int32,_H2StreamState}
end

function _h2_state(user_data::Ptr{Cvoid})::Base.RefValue{_H2ConnState}
    ptr = user_data == C_NULL ? nothing : unsafe_pointer_to_objref(Ptr{Nothing}(user_data))
    ptr === nothing && throw(ArgumentError("HTTP/2 user data missing"))
    return ptr::Base.RefValue{_H2ConnState}
end

function _h2_stream!(state::_H2ConnState, stream_id::Integer)
    key = Int32(stream_id)
    haskey(state.streams, key) && return state.streams[key]
    stream = _H2StreamState(nothing, nothing, Headers(), UInt8[], false, false, false, nothing, nothing, 1)
    state.streams[key] = stream
    return stream
end

function _h2_request_headers!(stream::_H2StreamState, name::AbstractString, value::AbstractString)
    if name == ":method"
        stream.method = String(value)
    elseif name == ":path"
        stream.target = String(value)
    elseif name == ":authority"
        haskey(stream.headers, "Host") || (stream.headers["Host"] = String(value))
    elseif !startswith(name, ":")
        appendheader!(stream.headers, name => value)
    end
    return stream
end

function _h2_response_body_read_callback(session::Ptr{NghttpWrapper.nghttp2_session},
                                         stream_id::Int32,
                                         buf::Ptr{UInt8},
                                         len::Csize_t,
                                         data_flags::Ptr{UInt32},
                                         source::Ptr{NghttpWrapper.nghttp2_data_source},
                                         user_data::Ptr{Cvoid})::Base.Cssize_t
    state = _h2_state(user_data)[]
    stream = get(state.streams, stream_id, nothing)
    stream === nothing && return Base.Cssize_t(0)
    response = stream.response
    response === nothing && return Base.Cssize_t(0)
    body = response.body
    if body isa String
        ncode = ncodeunits(body)
        if stream.response_offset > ncode
            unsafe_store!(data_flags, NghttpWrapper.NGHTTP2_DATA_FLAG_EOF)
            return Base.Cssize_t(0)
        end
        remaining = ncode - stream.response_offset + 1
        n = min(remaining, Int(len))
        codeunits_body = codeunits(body)
        GC.@preserve body codeunits_body begin
            unsafe_copyto!(buf, pointer(codeunits_body, stream.response_offset), n)
        end
        stream.response_offset += n
        stream.response_offset > ncode && unsafe_store!(data_flags, NghttpWrapper.NGHTTP2_DATA_FLAG_EOF)
        return Base.Cssize_t(n)
    else
        nbytes = length(body)
        if stream.response_offset > nbytes
            unsafe_store!(data_flags, NghttpWrapper.NGHTTP2_DATA_FLAG_EOF)
            return Base.Cssize_t(0)
        end
        remaining = nbytes - stream.response_offset + 1
        n = min(remaining, Int(len))
        GC.@preserve body begin
            unsafe_copyto!(buf, pointer(body, stream.response_offset), n)
        end
        stream.response_offset += n
        stream.response_offset > nbytes && unsafe_store!(data_flags, NghttpWrapper.NGHTTP2_DATA_FLAG_EOF)
        return Base.Cssize_t(n)
    end
end

function _h2_write_response_headers(response::Response)
    headers = Pair{String,String}[]
    push!(headers, ":status" => string(response.status))
    has_content_length = false
    for (name, value) in response.headers
        startswith(name, ":") && continue
        _ascii_case_equal(name, "connection") && continue
        _ascii_case_equal(name, "transfer-encoding") && continue
        _ascii_case_equal(name, "keep-alive") && continue
        _ascii_case_equal(name, "proxy-connection") && continue
        _ascii_case_equal(name, "upgrade") && continue
        _ascii_case_equal(name, "content-length") && (has_content_length = true)
        push!(headers, lowercase(String(name)) => String(value))
    end
    if !has_content_length
        push!(headers, "content-length" => string(response_body_length(response.body)))
    end
    return headers
end

function _h2_submit_response!(session, stream_id::Int32, response::Response, state::_H2ConnState)
    headers = _h2_write_response_headers(response)
    stream = _h2_stream!(state, stream_id)
    stream.response = response
    stream.response_provider = nothing
    stream.response_offset = 1
    if response_body_length(response.body) == 0
        NghttpWrapper.submit_response2(session, stream_id, headers)
        return nothing
    end
    provider = Ref(NghttpWrapper.nghttp2_data_provider2(
        NghttpWrapper.nghttp2_data_source(C_NULL),
        @cfunction(_h2_response_body_read_callback, Base.Cssize_t,
                   (Ptr{NghttpWrapper.nghttp2_session}, Int32, Ptr{UInt8}, Csize_t, Ptr{UInt32}, Ptr{NghttpWrapper.nghttp2_data_source}, Ptr{Cvoid})),
    ))
    stream.response_provider = provider
    NghttpWrapper.submit_response2(session, stream_id, headers; data_prd=Ptr{Cvoid}(pointer_from_objref(provider)))
    return nothing
end

function _h2_process_stream!(session, stream_id::Int32, state::_H2ConnState)
    stream = get(state.streams, stream_id, nothing)
    stream === nothing && return nothing
    stream.responded && return nothing
    stream.responded = true
    response = try
        if stream.body_too_large
            _default_error_response(PayloadTooLargeError())
        else
            stream.method === nothing && throw(ErrorException("HTTP parse error (HTTP/2 missing :method)"))
            stream.target === nothing && throw(ErrorException("HTTP parse error (HTTP/2 missing :path)"))
            req = Request(stream.method, stream.target, 2, stream.headers, stream.body)
            state.handler(req)
        end
    catch err
        _default_error_response(err)
    end
    response isa Response || (response = _default_error_response(ErrorException("HTTP parse error (HTTP/2 invalid response)")))
    _h2_submit_response!(session, stream_id, response, state)
    return nothing
end

function _h2_on_begin_headers(session::Ptr{NghttpWrapper.nghttp2_session}, frame::Ptr{NghttpWrapper.nghttp2_frame}, user_data::Ptr{Cvoid})::Cint
    state = _h2_state(user_data)[]
    stream_id = unsafe_load(frame).hd.stream_id
    _h2_stream!(state, stream_id)
    return Cint(0)
end

function _h2_on_header(session::Ptr{NghttpWrapper.nghttp2_session},
                       frame::Ptr{NghttpWrapper.nghttp2_frame},
                       name::Ptr{UInt8}, namelen::Csize_t,
                       value::Ptr{UInt8}, valuelen::Csize_t,
                       flags::UInt8,
                       user_data::Ptr{Cvoid})::Cint
    state = _h2_state(user_data)[]
    stream_id = unsafe_load(frame).hd.stream_id
    stream = get(state.streams, stream_id, nothing)
    stream === nothing && return Cint(0)
    stream.headers_complete && return Cint(0)
    header_name = unsafe_string(name, Int(namelen))
    header_value = unsafe_string(value, Int(valuelen))
    _h2_request_headers!(stream, header_name, header_value)
    return Cint(0)
end

function _h2_on_data_chunk_recv(session::Ptr{NghttpWrapper.nghttp2_session},
                                flags::UInt8,
                                stream_id::Int32,
                                data::Ptr{UInt8},
                                len::Csize_t,
                                user_data::Ptr{Cvoid})::Cint
    state = _h2_state(user_data)[]
    stream = get(state.streams, stream_id, nothing)
    stream === nothing && return Cint(0)
    stream.body_too_large && return Cint(0)
    current = length(stream.body)
    current + Int(len) > state.max_content_size && begin
        stream.body_too_large = true
        return Cint(0)
    end
    _append_fragment!(stream.body, data, len)
    return Cint(0)
end

function _h2_on_frame_recv(session::Ptr{NghttpWrapper.nghttp2_session},
                           frame::Ptr{NghttpWrapper.nghttp2_frame},
                           user_data::Ptr{Cvoid})::Cint
    state = _h2_state(user_data)[]
    hd = unsafe_load(frame).hd
    stream = get(state.streams, hd.stream_id, nothing)
    stream === nothing && return Cint(0)
    if hd.type == 0x01
        stream.headers_complete = true
    end
    if (hd.flags & 0x01) != 0
        _h2_process_stream!(session, hd.stream_id, state)
    end
    return Cint(0)
end

function _h2_on_stream_close(session::Ptr{NghttpWrapper.nghttp2_session},
                             stream_id::Int32,
                             error_code::UInt32,
                             user_data::Ptr{Cvoid})::Cint
    state = _h2_state(user_data)[]
    delete!(state.streams, stream_id)
    return Cint(0)
end

function _install_h2_callbacks!(callbacks)
    NghttpWrapper.session_callbacks_set_on_begin_headers_callback!(callbacks, @cfunction(_h2_on_begin_headers, Cint, (Ptr{NghttpWrapper.nghttp2_session}, Ptr{NghttpWrapper.nghttp2_frame}, Ptr{Cvoid})))
    NghttpWrapper.session_callbacks_set_on_header_callback!(callbacks, @cfunction(_h2_on_header, Cint, (Ptr{NghttpWrapper.nghttp2_session}, Ptr{NghttpWrapper.nghttp2_frame}, Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, UInt8, Ptr{Cvoid})))
    NghttpWrapper.session_callbacks_set_on_data_chunk_recv_callback!(callbacks, @cfunction(_h2_on_data_chunk_recv, Cint, (Ptr{NghttpWrapper.nghttp2_session}, UInt8, Int32, Ptr{UInt8}, Csize_t, Ptr{Cvoid})))
    NghttpWrapper.session_callbacks_set_on_frame_recv_callback!(callbacks, @cfunction(_h2_on_frame_recv, Cint, (Ptr{NghttpWrapper.nghttp2_session}, Ptr{NghttpWrapper.nghttp2_frame}, Ptr{Cvoid})))
    NghttpWrapper.session_callbacks_set_on_stream_close_callback!(callbacks, @cfunction(_h2_on_stream_close, Cint, (Ptr{NghttpWrapper.nghttp2_session}, Int32, UInt32, Ptr{Cvoid})))
    return callbacks
end

function _drive_h2_connection!(session, sock::Sockets.TCPSocket, prefix::Union{Nothing,_PrefetchedBytes,AbstractVector{UInt8}})
    if prefix !== nothing
        initial = prefix isa _PrefetchedBytes ? prefix.bytes[prefix.index:end] : prefix
        isempty(initial) || _feed_h2!(session, sock, initial)
    end
    while isopen(sock)
        chunk = _read_chunk(sock)
        isempty(chunk) && break
        _feed_h2!(session, sock, chunk)
    end
    _flush_h2!(session, sock)
    return nothing
end

function _handle_http2_connection(sock::Sockets.TCPSocket, handler; max_content_size::Integer = typemax(Int), prefix::Union{Nothing,_PrefetchedBytes,AbstractVector{UInt8}} = nothing)
    state_ref = Ref(_H2ConnState(handler, Int(max_content_size), Dict{Int32,_H2StreamState}()))
    callbacks = NghttpWrapper.callbacks_new()
    session = nothing
    err = nothing
    try
        _install_h2_callbacks!(callbacks)
        session = NghttpWrapper.Session(:server; callbacks=callbacks, user_data=Base.pointer_from_objref(state_ref))
        GC.@preserve state_ref callbacks session _drive_h2_connection!(session, sock, prefix)
    catch e
        err = e
    finally
        session !== nothing && NghttpWrapper.session_del!(session)
        NghttpWrapper.callbacks_del!(callbacks)
        close(sock)
    end
    err === nothing || throw(err)
    return nothing
end

function _feed_h2!(session, sock::Sockets.TCPSocket, chunk::AbstractVector{UInt8})
    code = NghttpWrapper.session_mem_recv2(session, chunk)
    code >= 0 || throw(ErrorException("HTTP/2 parse error ($(NghttpWrapper.error_name(code)))"))
    _flush_h2!(session, sock)
    return nothing
end

function _flush_h2!(session, sock::Sockets.TCPSocket)
    while true
        bytes = NghttpWrapper.session_mem_send_bytes(session)
        isempty(bytes) && return nothing
        write(sock, bytes)
        flush(sock)
    end
end
