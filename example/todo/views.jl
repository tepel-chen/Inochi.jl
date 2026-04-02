function todo_view(todo::Todo)::Dict{String,Any}
    return Dict(
        "id" => todo.id,
        "title" => todo.title,
        "checked" => todo.done,
        "state_class" => todo.done ? "todo-item is-done" : "todo-item",
        "status_text" => todo.done ? "Done" : "Open",
    )
end

function render_index_data(store::TodoStore)::Dict{String,Any}
    todos = list_todos(store)
    total = length(todos)
    completed = count(todo -> todo.done, todos)

    return Dict(
        "todos" => todo_view.(todos),
        "has_todos" => !isempty(todos),
        "total" => total,
        "pending" => total - completed,
        "completed" => completed,
    )
end
