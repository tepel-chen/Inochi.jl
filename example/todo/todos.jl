function build_todos_app(store::TodoStore)::App
    app = App()

    post(app, "/") do ctx
        form = ctx.reqform()
        title = strip(get(form, "title", ""))

        if !isempty(title)
            create_todo!(store, title)
        end

        return redirect(ctx, "/")
    end

    post(app, "/:id/toggle") do ctx
        todo_id = tryparse(Int, ctx.params["id"])
        todo_id !== nothing && toggle_todo!(store, todo_id)
        return redirect(ctx, "/")
    end

    post(app, "/:id/delete") do ctx
        todo_id = tryparse(Int, ctx.params["id"])
        todo_id !== nothing && delete_todo!(store, todo_id)
        return redirect(ctx, "/")
    end

    return app
end
