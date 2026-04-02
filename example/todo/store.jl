mutable struct Todo
    id::Int
    title::String
    done::Bool
end

mutable struct TodoStore
    todos::Vector{Todo}
    next_id::Int
    lock::ReentrantLock
end

TodoStore() = TodoStore(Todo[], 1, ReentrantLock())

function list_todos(store::TodoStore)::Vector{Todo}
    lock(store.lock) do
        return [Todo(todo.id, todo.title, todo.done) for todo in store.todos]
    end
end

function create_todo!(store::TodoStore, title::AbstractString)::Todo
    normalized_title = strip(String(title))
    lock(store.lock) do
        todo = Todo(store.next_id, normalized_title, false)
        push!(store.todos, todo)
        store.next_id += 1
        return todo
    end
end

function toggle_todo!(store::TodoStore, todo_id::Integer)::Bool
    lock(store.lock) do
        for todo in store.todos
            if todo.id == todo_id
                todo.done = !todo.done
                return true
            end
        end
        return false
    end
end

function delete_todo!(store::TodoStore, todo_id::Integer)::Bool
    lock(store.lock) do
        index = findfirst(todo -> todo.id == todo_id, store.todos)
        index === nothing && return false
        deleteat!(store.todos, index)
        return true
    end
end
