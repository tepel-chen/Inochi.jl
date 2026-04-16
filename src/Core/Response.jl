struct Response
    status::Int
    headers::Headers
    body::Union{String,Vector{UInt8}}
    Response(status::Int, headers::Headers, body::String) = new(status, headers, body)
    Response(status::Int, headers::Headers, body::Vector{UInt8}) = new(status, headers, body)
end
Response(status::Integer=200, headers::AbstractDict{<:AbstractString,<:AbstractString}=Dict{String,String}(), body::AbstractString="") = Response(Int(status), _normalize_headers(headers), body isa String ? body : String(body))
Response(status::Integer, headers::AbstractDict{<:AbstractString,<:AbstractString}, body::AbstractVector{UInt8}) = Response(Int(status), _normalize_headers(headers), collect(body))
Response(status::Integer, headers::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}, body::AbstractString) = Response(Int(status), _normalize_headers(headers), body isa String ? body : String(body))
Response(status::Integer, headers::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}, body::AbstractVector{UInt8}) = Response(Int(status), _normalize_headers(headers), collect(body))
Response(status::Integer, headers::AbstractVector{<:Pair{<:AbstractString,<:AbstractString}}) = Response(Int(status), _normalize_headers(headers), "")
Response(status::Integer, body::AbstractString) = Response(Int(status), Headers(), body isa String ? body : String(body))
Response(status::Integer, body::AbstractVector{UInt8}) = Response(Int(status), Headers(), body)
Response(status::Integer, headers::Headers) = Response(Int(status), headers, "")
response_body_length(body::Vector{UInt8}) = length(body)
response_body_length(body::AbstractString) = ncodeunits(body)
function _write_status_line(io::IO, status::Integer); write(io, "HTTP/1.1 "); print(io, status); reason = LlhttpWrapper.status_name(status); if !isempty(reason); write(io, " "); write(io, reason); end; write(io, "\r\n"); end
function _write_response(io::IO, response::Response); _write_status_line(io, response.status); has_content_length = false; has_connection = false; for (name, value) in response.headers; _validate_header!(name, value); if _ascii_case_equal(name, "content-length"); has_content_length = true; elseif _ascii_case_equal(name, "connection"); has_connection = true; end; write(io, name, ": ", value, "\r\n"); end; if !has_content_length; write(io, "Content-Length: "); print(io, response_body_length(response.body)); write(io, "\r\n"); end; has_connection || write(io, "Connection: close\r\n"); write(io, "\r\n"); write(io, response.body); flush(io); return io end
_default_error_response(err) = err isa PayloadTooLargeError ? Response(413, Dict("Content-Type" => "text/plain; charset=utf-8"), "Payload Too Large\n") : err isa ErrorException && startswith(err.msg, "HTTP parse error") ? Response(400, Dict("Content-Type" => "text/plain; charset=utf-8"), "Bad Request\n") : Response(500, Dict("Content-Type" => "text/plain; charset=utf-8"), "Internal Server Error\n")
function _handle_http1_connection(io::IO, handler; max_content_size::Integer = typemax(Int), prefix = nothing); state_ref = Ref(_RequestState(max_content_size)); parser = LlhttpWrapper.Parser(LlhttpWrapper.HTTP_REQUEST; settings=_parser_settings()); LlhttpWrapper.set_userdata!(parser, Base.pointer_from_objref(state_ref)); try; GC.@preserve state_ref parser begin; while true; queued = _next_request!(io, parser, state_ref, prefix); queued === nothing && break; response = handler(queued.request); response isa Response || throw(ArgumentError("handler must return Core.Response")); _write_response(io, response); queued.keep_alive || break; end; end; catch err; _write_response(io, _default_error_response(err)); finally; close(io); end; return nothing end

function _configure_tls!(sslconfig::OpenSSL.SSLContext, allow_http1::Bool, allow_http2::Bool)
    allow_http1 || allow_http2 || throw(ArgumentError("allow_http1 and allow_http2 cannot both be false"))
    allow_http2 && allow_http1 && return OpenSSL.ssl_set_alpn(sslconfig, OpenSSL.UPDATE_HTTP2_ALPN)
    allow_http2 && return OpenSSL.ssl_set_alpn(sslconfig, OpenSSL.HTTP2_ALPN)
    return OpenSSL.ssl_set_alpn(sslconfig, "\x08http/1.1")
end

function _wrap_tls(sock::Sockets.TCPSocket, sslconfig::OpenSSL.SSLContext)
    tls = OpenSSL.SSLStream(sslconfig, sock)
    try
        while true
            Base.@lock tls.lock begin
                tls.closed && throw(ArgumentError("ssl stream already closed"))
                OpenSSL.clear_errors!()
                ret = ccall(
                    (:SSL_accept, OpenSSL.libssl),
                    Cint,
                    (OpenSSL.SSL,),
                    tls.ssl,
                )
                if ret == 1
                    ccall(
                        (:SSL_set_read_ahead, OpenSSL.libssl),
                        Cvoid,
                        (OpenSSL.SSL, Cint),
                        tls.ssl,
                        Int32(1),
                    )
                    return tls
                end
                err = OpenSSL.get_error(tls.ssl, ret)
                if err == OpenSSL.SSL_ERROR_WANT_READ
                    eof(tls.io) && throw(EOFError())
                elseif err == OpenSSL.SSL_ERROR_WANT_WRITE
                    flush(tls.io)
                else
                    throw(Base.IOError(OpenSSL.OpenSSLError(err).msg, 0))
                end
            end
        end
    catch
        close(tls)
        rethrow()
    end
    return tls
end

function _handle_tls_connection(sock::Sockets.TCPSocket, handler, sslconfig::OpenSSL.SSLContext; max_content_size::Integer = typemax(Int), allow_http1::Bool = true, allow_http2::Bool = true)
    _configure_tls!(sslconfig, allow_http1, allow_http2)
    tls = _wrap_tls(sock, sslconfig)
    sniffed = _sniff_protocol(tls; allow_http1=allow_http1, allow_http2=allow_http2)
    sniffed === nothing && (close(tls); return nothing)
    protocol, prefix = sniffed
    protocol === :http2 && return _handle_http2_connection(tls, handler; max_content_size=max_content_size, prefix=prefix)
    protocol === :http1 && return _handle_http1_connection(tls, handler; max_content_size=max_content_size, prefix=prefix)
    close(tls)
    return nothing
end

function _handle_tls_connection(sock::Sockets.TCPSocket, handler, sslconfig; max_content_size::Integer = typemax(Int), allow_http1::Bool = true, allow_http2::Bool = true)
    throw(ArgumentError("sslconfig must be an OpenSSL.SSLContext"))
end

function _handle_connection(sock::Sockets.TCPSocket, handler; max_content_size::Integer = typemax(Int), allow_http1::Bool = true, allow_http2::Bool = true, sslconfig = nothing)
    allow_http1 || allow_http2 || throw(ArgumentError("allow_http1 and allow_http2 cannot both be false"))
    if sslconfig !== nothing
        return _handle_tls_connection(sock, handler, sslconfig; max_content_size=max_content_size, allow_http1=allow_http1, allow_http2=allow_http2)
    end
    sniffed = _sniff_protocol(sock; allow_http1=allow_http1, allow_http2=allow_http2)
    sniffed === nothing && (close(sock); return nothing)
    protocol, prefix = sniffed
    protocol === :http2 && return _handle_http2_connection(sock, handler; max_content_size=max_content_size, prefix=prefix)
    protocol === :http1 && return _handle_http1_connection(sock, handler; max_content_size=max_content_size, prefix=prefix)
    close(sock)
    return nothing
end

_normalize_host(host::AbstractString) = getaddrinfo(host)

"""
    serve(handler; host = "127.0.0.1", port = 8080, backlog = 128, max_content_size = typemax(Int), allow_http1 = true, allow_http2 = true, sslconfig = nothing)

Start an HTTP server for `handler`.

Pass an `OpenSSL.SSLContext` configured with a server certificate and private key to serve HTTPS.
When TLS is enabled, `allow_http2` and `allow_http1` control the advertised ALPN list.
"""
function serve(handler; host::AbstractString="127.0.0.1", port::Integer=8080, backlog::Integer=128, max_content_size::Integer=typemax(Int), allow_http1::Bool=true, allow_http2::Bool=true, sslconfig = nothing)
    serve(handler, listen(_normalize_host(host), port; backlog=backlog); max_content_size=max_content_size, allow_http1=allow_http1, allow_http2=allow_http2, sslconfig=sslconfig)
end
function serve(handler, listener::Sockets.TCPServer; max_content_size::Integer = typemax(Int), allow_http1::Bool=true, allow_http2::Bool=true, sslconfig = nothing); while true; sock = try accept(listener) catch; isopen(listener) || return nothing; return nothing end; @async _handle_connection(sock, handler; max_content_size=max_content_size, allow_http1=allow_http1, allow_http2=allow_http2, sslconfig=sslconfig); end; return nothing end
