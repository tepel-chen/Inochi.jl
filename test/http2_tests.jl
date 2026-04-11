using NghttpWrapper

function _call_h2_header!(session, frame, name::AbstractString, value::AbstractString, user_data)
    name_bytes = collect(codeunits(name))
    value_bytes = collect(codeunits(value))
    GC.@preserve name_bytes value_bytes begin
        return InochiCore._h2_on_header(
            Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_session}, session),
            Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_frame}, frame),
            pointer(name_bytes), UInt64(length(name_bytes)),
            pointer(value_bytes), UInt64(length(value_bytes)),
            UInt8(0),
            user_data,
        )
    end
end

function _make_h2_client_request_bytes(headers)
    callbacks = NghttpWrapper.callbacks_new()
    option = NghttpWrapper.option_new()
    session = NghttpWrapper.Session(:client; callbacks=callbacks, option=option)
    try
        preface = NghttpWrapper.session_mem_send_bytes(session)
        @test !isempty(preface)
        @test NghttpWrapper.submit_request(session, headers) == 1
        request_bytes = NghttpWrapper.session_mem_send_bytes(session)
        return vcat(preface, request_bytes)
    finally
        NghttpWrapper.session_del!(session)
        NghttpWrapper.option_del!(option)
        NghttpWrapper.callbacks_del!(callbacks)
    end
end

function _make_h2_state(handler)
    return Ref(InochiCore._H2ConnState(handler, typemax(Int), Dict{Int32,InochiCore._H2StreamState}()))
end

function _call_h2_response_body_read_callback(response, stream_id::Int32; response_offset::Int = 1, buflen::Int = 3)
    state_ref = _make_h2_state(req -> Response(200, ["Content-Type" => "text/plain"], "unused"))
    stream = InochiCore._h2_stream!(state_ref[], stream_id)
    stream.response = response
    stream.response_offset = response_offset
    callbacks = NghttpWrapper.callbacks_new()
    session = NghttpWrapper.Session(:server; callbacks=callbacks, user_data=Base.pointer_from_objref(state_ref))
    source = Ref(NghttpWrapper.nghttp2_data_source(C_NULL))
    session_ptr = Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_session}, session)
    source_ptr = Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_data_source}, source)
    buf = Vector{UInt8}(undef, buflen)
    flags = Ref{UInt32}(0)
    try
        GC.@preserve buf flags state_ref session source begin
            n = InochiCore._h2_response_body_read_callback(
                session_ptr,
                stream_id,
                pointer(buf),
                Csize_t(length(buf)),
                Base.unsafe_convert(Ptr{UInt32}, flags),
                source_ptr,
                Base.pointer_from_objref(state_ref),
            )
            return n, buf, flags[]
        end
    finally
        NghttpWrapper.session_del!(session)
        NghttpWrapper.callbacks_del!(callbacks)
    end
end

@testset "HTTP/2" begin
    @testset "sniff" begin
        with_tcp_pair() do sock, client, server
            close(client)
            @test_throws ArgumentError InochiCore._sniff_protocol(sock; allow_http1=false, allow_http2=false)
            proto, prefetched = InochiCore._sniff_protocol(sock; allow_http1=true, allow_http2=false)
            @test proto == :http1
            @test prefetched.bytes == UInt8[]
            @test prefetched.index == 1
        end

        with_tcp_pair() do sock, client, server
            write(client, Vector{UInt8}(codeunits("NOT-H2")))
            flush(client)
            @test isnothing(InochiCore._sniff_protocol(sock; allow_http1=false, allow_http2=true))
        end

        with_tcp_pair() do sock, client, server
            write(client, Vector{UInt8}(codeunits(NghttpWrapper.NGHTTP2_CLIENT_MAGIC)))
            flush(client)
            proto, prefetched = InochiCore._sniff_protocol(sock; allow_http1=true, allow_http2=true)
            @test proto == :http2
            @test String(prefetched.bytes) == NghttpWrapper.NGHTTP2_CLIENT_MAGIC
        end

        with_tcp_pair() do sock, client, server
            magic = Vector{UInt8}(codeunits(NghttpWrapper.NGHTTP2_CLIENT_MAGIC))
            write(client, magic[1:5])
            flush(client)
            writer = @async begin
                yield()
                write(client, magic[6:end])
                flush(client)
            end
            proto, prefetched = InochiCore._sniff_protocol(sock; allow_http1=true, allow_http2=true)
            wait(writer)
            @test proto == :http2
            @test String(prefetched.bytes) == NghttpWrapper.NGHTTP2_CLIENT_MAGIC
        end

        with_tcp_pair() do sock, client, server
            close(client)
            prefetched = InochiCore._PrefetchedBytes(UInt8[])
            @test InochiCore._read_chunk(sock, prefetched) == UInt8[]
            prefetched2 = InochiCore._PrefetchedBytes(UInt8[0x61, 0x62])
            @test InochiCore._read_chunk(sock, prefetched2) == UInt8[0x61, 0x62]
        end
    end

    @testset "callbacks" begin
        version_seen = Ref{Any}(nothing)
        state_ref = Ref(InochiCore._H2ConnState(req -> begin
            version_seen[] = req.version
            return Response(200, ["Content-Type" => "text/plain; charset=utf-8"], "h2-ok")
        end, typemax(Int), Dict{Int32,InochiCore._H2StreamState}()))

        callbacks = NghttpWrapper.callbacks_new()
        session = NghttpWrapper.Session(:server; callbacks = callbacks, user_data = Base.pointer_from_objref(state_ref))
        frame = Ref(NghttpWrapper.nghttp2_frame(NghttpWrapper.nghttp2_frame_hd(0, Int32(1), UInt8(0x01), UInt8(0x05), UInt8(0x00))))
        session_ptr = Ptr{NghttpWrapper.nghttp2_session}(C_NULL)
        frame_ptr = Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_frame}, frame)

        try
            user_data = Base.pointer_from_objref(state_ref)
            @test InochiCore._h2_on_begin_headers(
                Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_session}, session),
                frame_ptr,
                user_data,
            ) == 0
            @test _call_h2_header!(session, frame, ":method", "GET", user_data) == 0
            @test _call_h2_header!(session, frame, ":path", "/h2", user_data) == 0
            @test _call_h2_header!(session, frame, ":scheme", "http", user_data) == 0
            @test _call_h2_header!(session, frame, ":authority", "127.0.0.1:8080", user_data) == 0
            @test _call_h2_header!(session, frame, "x-custom", "value", user_data) == 0
            @test state_ref[].streams[Int32(1)].headers["x-custom"] == "value"
            @test InochiCore._h2_on_frame_recv(
                Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_session}, session),
                frame_ptr,
                user_data,
            ) == 0

            @test version_seen[] == 2
        finally
            NghttpWrapper.session_del!(session)
            NghttpWrapper.callbacks_del!(callbacks)
        end
    end

    @testset "response body callback" begin
        n1, buf1, flags1 = _call_h2_response_body_read_callback(Response(200, ["Content-Type" => "text/plain"], "abc"), Int32(1); response_offset = 1, buflen = 3)
        @test n1 == 3
        @test String(buf1) == "abc"
        @test flags1 == NghttpWrapper.NGHTTP2_DATA_FLAG_EOF

        n1b, buf1b, flags1b = _call_h2_response_body_read_callback(Response(200, ["Content-Type" => "text/plain"], "abc"), Int32(11); response_offset = 4, buflen = 3)
        @test n1b == 0
        @test flags1b == NghttpWrapper.NGHTTP2_DATA_FLAG_EOF

        n2, buf2, flags2 = _call_h2_response_body_read_callback(Response(200, ["Content-Type" => "text/plain"], "abc"), Int32(2); response_offset = 1, buflen = 2)
        @test n2 == 2
        @test String(buf2) == "ab"
        @test flags2 == 0

        n3, buf3, flags3 = _call_h2_response_body_read_callback(Response(200, ["Content-Type" => "text/plain"], UInt8[0x78, 0x79]), Int32(3); response_offset = 1, buflen = 3)
        @test n3 == 2
        @test buf3[1:2] == UInt8[0x78, 0x79]
        @test flags3 == NghttpWrapper.NGHTTP2_DATA_FLAG_EOF

        n4, buf4, flags4 = _call_h2_response_body_read_callback(Response(200, ["Content-Type" => "text/plain"], UInt8[0x78, 0x79]), Int32(4); response_offset = 3, buflen = 3)
        @test n4 == 0
        @test flags4 == NghttpWrapper.NGHTTP2_DATA_FLAG_EOF
    end

    @testset "stream lifecycle" begin
        state_ref = Ref(InochiCore._H2ConnState(req -> Response(200, ["Content-Type" => "text/plain"], "ok"), typemax(Int), Dict{Int32,InochiCore._H2StreamState}()))
        stream = InochiCore._h2_stream!(state_ref[], Int32(7))
        @test stream.method === nothing
        callbacks = NghttpWrapper.callbacks_new()
        session = NghttpWrapper.Session(:server; callbacks=callbacks, user_data=Base.pointer_from_objref(state_ref))
        session_ptr = Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_session}, session)
        data1 = UInt8[0x61, 0x62]
        GC.@preserve data1 state_ref begin
            @test InochiCore._h2_on_data_chunk_recv(
                session_ptr,
                0x00,
                Int32(7),
                pointer(data1),
                Csize_t(2),
                Base.pointer_from_objref(state_ref),
            ) == 0
        end
        @test stream.body == UInt8[0x61, 0x62]
        data2 = UInt8[0x63]
        GC.@preserve data2 state_ref begin
            @test InochiCore._h2_on_data_chunk_recv(
                session_ptr,
                0x00,
                Int32(7),
                pointer(data2),
                Csize_t(1),
                Base.pointer_from_objref(state_ref),
            ) == 0
        end
        @test stream.body == UInt8[0x61, 0x62, 0x63]
        stream2 = InochiCore._h2_stream!(state_ref[], Int32(8))
        state_ref[].max_content_size = 2
        data3 = UInt8[0x61, 0x62, 0x63]
        GC.@preserve data3 state_ref begin
            @test InochiCore._h2_on_data_chunk_recv(
                session_ptr,
                0x00,
                Int32(8),
                pointer(data3),
                Csize_t(3),
                Base.pointer_from_objref(state_ref),
            ) == 0
        end
        @test stream2.body_too_large
        frame_too_large = Ref(NghttpWrapper.nghttp2_frame(NghttpWrapper.nghttp2_frame_hd(0, Int32(8), UInt8(0x01), UInt8(0x05), UInt8(0x00))))
        stream2.method = "GET"
        stream2.target = "/too-large"
        @test InochiCore._h2_on_frame_recv(
            session_ptr,
            Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_frame}, frame_too_large),
            Base.pointer_from_objref(state_ref),
        ) == 0

        frame = Ref(NghttpWrapper.nghttp2_frame(NghttpWrapper.nghttp2_frame_hd(0, Int32(7), UInt8(0x01), UInt8(0x01), UInt8(0x00))))
        state_ref[].handler = req -> Response(204, Headers())
        stream.method = "GET"
        stream.target = "/x"
        @test InochiCore._h2_on_frame_recv(
            session_ptr,
            Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_frame}, frame),
            Base.pointer_from_objref(state_ref),
        ) == 0
        @test stream.headers_complete
        @test stream.responded

        @test InochiCore._h2_on_stream_close(
            session_ptr,
            Int32(7),
            UInt32(0),
            Base.pointer_from_objref(state_ref),
        ) == 0
        @test !haskey(state_ref[].streams, Int32(7))
        NghttpWrapper.session_del!(session)
        NghttpWrapper.callbacks_del!(callbacks)
    end

    @testset "callbacks and connection" begin
        callbacks = NghttpWrapper.callbacks_new()
        try
            @test InochiCore._install_h2_callbacks!(callbacks) === callbacks
        finally
            NghttpWrapper.callbacks_del!(callbacks)
        end

        version_seen = Ref{Any}(nothing)
        request_seen = Ref{Any}(nothing)
        state_ref = _make_h2_state(req -> begin
            version_seen[] = req.version
            request_seen[] = (req.method, req.target, req.headers["Host"])
            return Response(204, Headers())
        end)
        callbacks2 = NghttpWrapper.callbacks_new()
        session = NghttpWrapper.Session(:server; callbacks=callbacks2, user_data=Base.pointer_from_objref(state_ref))
        try
            stream = InochiCore._h2_stream!(state_ref[], Int32(11))
            stream.method = "GET"
            stream.target = "/h2"
            stream.headers["Host"] = "127.0.0.1:8080"
            stream.headers_complete = true
            @test InochiCore._h2_process_stream!(Base.unsafe_convert(Ptr{NghttpWrapper.nghttp2_session}, session), Int32(11), state_ref[]) === nothing
            @test version_seen[] == 2
            @test request_seen[] == ("GET", "/h2", "127.0.0.1:8080")
            @test stream.responded
        finally
            NghttpWrapper.session_del!(session)
            NghttpWrapper.callbacks_del!(callbacks2)
        end
    end

    @testset "connection loop" begin
        with_tcp_pair() do sock, client, server
            request_bytes = _make_h2_client_request_bytes([
                ":method" => "GET",
                ":path" => "/h2-loop",
                ":scheme" => "http",
                ":authority" => "127.0.0.1:8080",
            ])
            magic = collect(codeunits(NghttpWrapper.NGHTTP2_CLIENT_MAGIC))
            rest = request_bytes[length(magic) + 1:end]
            seen = Ref(false)
            task = @async InochiCore._handle_http2_connection(sock, req -> begin
                seen[] = true
                Response(204, Headers())
            end; prefix = magic)
            sleep(0.05)
            isempty(rest) || write(client, rest)
            flush(client)
            sleep(0.2)
            closewrite(client)
            @test fetch(task) === nothing
        end
    end
end
