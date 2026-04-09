# Changelog

## 0.2.0

Released after `v0.1.0`.

### Breaking Changes

- Removed the old `ctx.render` / `ctx.req*` property-style helpers in favor of function calls such as `render(ctx, ...)` and `reqtext(ctx)`.

### Added

- Added built-in middlewares: `csrf()` and `etag()`.
- `ctx.backtrace` for error reporting.
- `reqfile(ctx)` for multipart uploads.
- `max_content_size` app configuration.
- `ETag` support for static files.
- Signed cookie helpers: `secure_cookie` and `set_secure_cookie`.

### Changed

- The request/response helper API was consolidated around `ctx`.
- The server now adds some default headers: `Vary`, `Server`, and `Date`.

### Fixed

- Removed dead code and tightened tests.

