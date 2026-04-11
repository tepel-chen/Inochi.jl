"""
    Response

Minimal HTTP response representation.
"""
struct Response
    status::Int
    headers::Headers
    body::Union{String,Vector{UInt8}}

    function Response(status::Int, headers::Headers, body::String)
        return new(status, headers, body)
    end

    function Response(status::Int, headers::Headers, body::Vector{UInt8})
        return new(status, headers, body)
    end
end

Response(status::Integer=200,
         headers::AbstractDict{<:AbstractString,<:AbstractString}=Dict{String,String}(),
         body::AbstractString="") =
    Response(Int(status), _normalize_headers(headers), body isa String ? body : String(body))

Response(status::Integer,
         headers::AbstractDict{<:AbstractString,<:AbstractString},
         body::AbstractVector{UInt8}) =
    Response(Int(status), _normalize_headers(headers), collect(body))

Response(status::Integer,
         headers::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}},
         body::AbstractString) =
    Response(Int(status), _normalize_headers(headers), body isa String ? body : String(body))

Response(status::Integer,
         headers::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}},
         body::AbstractVector{UInt8}) =
    Response(Int(status), _normalize_headers(headers), collect(body))
Response(status::Integer,
         headers::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}) =
    Response(Int(status), _normalize_headers(headers), "")

Response(status::Integer, body::AbstractString) = Response(Int(status), Headers(), body isa String ? body : String(body))
Response(status::Integer, body::AbstractVector{UInt8}) = Response(Int(status), Headers(), body)
Response(status::Integer, headers::Headers, body::AbstractString) =
    Response(Int(status), headers, body isa String ? body : String(body))
Response(status::Integer, headers::Headers, body::AbstractVector{UInt8}) =
    Response(Int(status), headers, collect(body))
Response(status::Integer, headers::Headers) = Response(Int(status), headers, "")

function response_body_length(body::Vector{UInt8})
    return length(body)
end

function response_body_length(body::AbstractString)
    return ncodeunits(body)
end

function _write_status_line(io::IO, status::Integer)
    write(io, "HTTP/1.1 ")
    print(io, status)
    reason = try
        LlhttpWrapper.status_name(status)
    catch
        ""
    end
    if !isempty(reason)
        write(io, ' ')
        write(io, reason)
    end
    write(io, "\r\n")
    return io
end

function _write_response(io::IO, response::Response)
    _write_status_line(io, response.status)
    has_content_length = false
    has_connection = false
    for (name, value) in response.headers
        _validate_header!(name, value)
        if _ascii_case_equal(name, "content-length")
            has_content_length = true
        elseif _ascii_case_equal(name, "connection")
            has_connection = true
        end
        write(io, name, ": ", value, "\r\n")
    end
    if !has_content_length
        write(io, "Content-Length: ")
        print(io, response_body_length(response.body))
        write(io, "\r\n")
    end
    has_connection || write(io, "Connection: close\r\n")
    write(io, "\r\n")
    write(io, response.body)
    return io
end

function _default_error_response(err)
    if err isa PayloadTooLargeError
        return Response(413, Dict("Content-Type" => "text/plain; charset=utf-8"), "Payload Too Large\n")
    end
    if err isa ErrorException && startswith(err.msg, "HTTP parse error")
        return Response(400, Dict("Content-Type" => "text/plain; charset=utf-8"), "Bad Request\n")
    end
    return Response(500, Dict("Content-Type" => "text/plain; charset=utf-8"), "Internal Server Error\n")
end

function _handle_connection(sock::Sockets.TCPSocket, handler; max_content_size::Integer = typemax(Int))
    state_ref = Ref(_RequestState(max_content_size))
    parser = LlhttpWrapper.Parser(LlhttpWrapper.HTTP_REQUEST; settings=_parser_settings())
    LlhttpWrapper.set_userdata!(parser, Base.pointer_from_objref(state_ref))
    try
        GC.@preserve state_ref parser begin
            while true
                queued = _next_request!(sock, parser, state_ref)
                queued === nothing && break
                response = handler(queued.request)
                response isa Response || throw(ArgumentError("handler must return Core.Response"))
                _write_response(sock, response)
                queued.keep_alive || break
            end
        end
    catch err
        _write_response(sock, _default_error_response(err))
    finally
        close(sock)
    end
    return nothing
end

function _normalize_host(host::AbstractString)
    try
        return parse(Sockets.IPAddr, host)
    catch
        return getaddrinfo(host)
    end
end

"""
    serve(handler; host="127.0.0.1", port=8080, backlog=128)

Start a minimal HTTP server that dispatches each request to `handler`.
The handler must accept a `Request` and return a `Response`.
"""
function serve(handler; host::AbstractString="127.0.0.1", port::Integer=8080, backlog::Integer=128, max_content_size::Integer=typemax(Int))
    serve(listen(_normalize_host(host), port; backlog=backlog), handler; max_content_size=max_content_size)
end

function serve(listener::Sockets.TCPServer, handler; max_content_size::Integer = typemax(Int))
    while true
        sock = try
            accept(listener)
        catch err
            isopen(listener) || return nothing
            rethrow(err)
        end
        @async _handle_connection(sock, handler; max_content_size=max_content_size)
    end
end

serve(handler, listener::Sockets.TCPServer; max_content_size::Integer = typemax(Int)) = serve(listener, handler; max_content_size=max_content_size)
