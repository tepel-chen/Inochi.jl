# Todo App

The repository includes a small in-memory todo example at:

- `example/todo`

Key files:

- `app.jl`: application routes and server startup
- `store.jl`: in-memory todo store
- `views.jl`: HTML rendering helpers
- `README.md`: run instructions
- `public/app.css`: static stylesheet
- `public/about.html`: fixed file served with `sendFile`

## What It Demonstrates

- `App()` setup
- `get`, `post`, and dynamic params
- `reqform(ctx)` for form posts
- `route(app, "/todos", todos_app)` for splitting a feature into a mounted sub app
- `html(ctx, ...)` for HTML responses
- `redirect(ctx, "/")` after mutations
- `static(...)` for assets
- `sendFile(...)` for a fixed page
- `render(ctx, ...)` with `IwaiEngine.jl` configured through `app.file_renderer`

## Run It

```bash
cd example/todo
julia app.jl
```

Open `http://127.0.0.1:8080`.
The app runs in the foreground and stops when you interrupt it.
