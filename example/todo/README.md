# Inochi Todo Example

Run:

```bash
cd example/todo
julia app.jl
```

Open `http://127.0.0.1:8080`.

Routes:

- `GET /` renders the todo board
- `POST /todos` adds a todo
- `POST /todos/:id/toggle` toggles completion
- `POST /todos/:id/delete` deletes a todo
- `GET /static/*` serves assets from `public/`
- `GET /about` serves a fixed file through `sendFile`
