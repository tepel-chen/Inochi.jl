# TLS with OpenSSL

```@meta
CurrentModule = Inochi
```

Inochi serves TLS through `OpenSSL.SSLContext`. The server expects you to
load a certificate and private key into that context before passing it as
`sslconfig`.

## Build a Server Context

```julia
using Inochi
using OpenSSL

ssl = OpenSSL.SSLContext(OpenSSL.TLSServerMethod())
OpenSSL.ssl_use_certificate(ssl, OpenSSL.X509Certificate(read("cert.pem", String)))
OpenSSL.ssl_use_private_key(ssl, OpenSSL.EvpPKey(read("key.pem", String)))
```

## Serve HTTPS

```julia
app = App()

get(app, "/") do ctx
    text(ctx, "hello over tls")
end

start(app; host = "0.0.0.0", port = 8443, sslconfig = ssl)
```

## ALPN Behavior

When TLS is enabled, Inochi advertises ALPN based on the route flags:

- `allow_http1 = true, allow_http2 = true` advertises `h2` and `http/1.1`
- `allow_http1 = false, allow_http2 = true` advertises `h2`
- `allow_http1 = true, allow_http2 = false` advertises `http/1.1`

After the handshake, Inochi inspects the encrypted stream and dispatches to
the HTTP/1.1 or HTTP/2 handler path accordingly.
