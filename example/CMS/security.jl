using Base64
using Random

function generate_csp_nonce()::String
    return base64encode(rand(RandomDevice(), UInt8, 16))
end

function csp_middleware()
    return function (ctx)
        nonce = generate_csp_nonce()
        set!(ctx, :csp_nonce, nonce)

        policy = join([
            "default-src 'self'",
            "base-uri 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
            "img-src 'self' data:",
            "object-src 'none'",
            "script-src 'self' 'nonce-" * nonce * "' https://cdn.tailwindcss.com",
            "style-src 'self' 'unsafe-inline'",
            "upgrade-insecure-requests",
        ], "; ")

        header!(ctx, "Content-Security-Policy", policy)
        header!(ctx, "Referrer-Policy", "strict-origin-when-cross-origin")
        header!(ctx, "X-Content-Type-Options", "nosniff")
        header!(ctx, "X-Frame-Options", "DENY")
        return ctx.next()
    end
end
