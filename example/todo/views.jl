function escape_html(value)::String
    escaped = replace(string(value), "&" => "&amp;")
    escaped = replace(escaped, "<" => "&lt;")
    escaped = replace(escaped, ">" => "&gt;")
    escaped = replace(escaped, "\"" => "&quot;")
    return replace(escaped, "'" => "&#39;")
end

function render_todo(todo::Todo)::String
    checked = todo.done ? "checked" : ""
    state_class = todo.done ? "todo-item is-done" : "todo-item"
    status_text = todo.done ? "Done" : "Open"

    return """
    <li class="$(state_class)">
      <div class="todo-main">
        <form action="/todos/$(todo.id)/toggle" method="post" class="toggle-form">
          <button class="toggle-button" type="submit" aria-label="Toggle todo $(todo.id)">
            <span class="checkbox $(checked)"></span>
          </button>
        </form>
        <div class="todo-copy">
          <p class="todo-title">$(escape_html(todo.title))</p>
          <p class="todo-meta">#$(todo.id) • $(status_text)</p>
        </div>
      </div>
      <form action="/todos/$(todo.id)/delete" method="post" class="delete-form">
        <button class="delete-button" type="submit">Delete</button>
      </form>
    </li>
    """
end

function render_index(store::TodoStore)::String
    todos = list_todos(store)
    items = isempty(todos) ? "<li class=\"empty-state\">No todos yet. Add your first task.</li>" : join(render_todo.(todos), "\n")
    total = length(todos)
    completed = count(todo -> todo.done, todos)
    pending = total - completed

    return """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Inochi Todo</title>
        <link rel="stylesheet" href="/static/app.css">
      </head>
      <body>
        <main class="shell">
          <section class="hero">
            <p class="eyebrow">Inochi Example</p>
            <h1>Todo board</h1>
            <p class="lede">A small in-memory todo app built with Inochi forms, params, static assets, and file responses.</p>
          </section>

          <section class="panel composer">
            <form action="/todos" method="post" class="composer-form">
              <label class="composer-label" for="title">New task</label>
              <div class="composer-row">
                <input id="title" name="title" type="text" placeholder="Ship the router rewrite" autocomplete="off">
                <button type="submit">Add</button>
              </div>
            </form>
          </section>

          <section class="panel stats">
            <div>
              <span class="stat-label">Total</span>
              <strong>$(total)</strong>
            </div>
            <div>
              <span class="stat-label">Open</span>
              <strong>$(pending)</strong>
            </div>
            <div>
              <span class="stat-label">Done</span>
              <strong>$(completed)</strong>
            </div>
            <a class="about-link" href="/about">About this example</a>
          </section>

          <section class="panel list-panel">
            <ul class="todo-list">
              $(items)
            </ul>
          </section>
        </main>
      </body>
    </html>
    """
end
