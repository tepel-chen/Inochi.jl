module Core

using Sockets
using LlhttpWrapper

include("Core/Headers.jl")
include("Core/Request.jl")
include("Core/Response.jl")

export Request, Response, Headers, PayloadTooLargeError, bodybytes, bodylength, bodytext, getheaders, appendheader!, serve
export LlhttpWrapper, LazyBody, _RequestState, _parser_settings, _next_completed_request, _header_value_range, _content_length, _read_chunk, _normalize_host, _default_error_response, _ascii_case_equal, _write_response

end
