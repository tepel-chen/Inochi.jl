function build_posts_app(store::CMSStore)::App
    app = App()

    get(app, "/:id") do ctx
        post_id = Base.parse(Int, ctx.params["id"])
        post = find_post(store, post_id)
        post === nothing && return text(ctx, "Post not found"; status = 404)
        post.published || current_user(ctx) !== nothing || return text(ctx, "Draft not found"; status = 404)
        increment_views!(store, post)
        return render(ctx, "posts/show.iwai", post_detail_view(store, ctx, post))
    end

    post(app, "/:id/comments") do ctx
        user = current_user(ctx)
        user === nothing && return redirect(ctx, "/login"; status = 303)
        post_id = Base.parse(Int, ctx.params["id"])
        post = find_post(store, post_id)
        post === nothing && return text(ctx, "Post not found"; status = 404)
        form = reqform(ctx)
        body = strip(get(form, "body", ""))
        isempty(body) && return render(ctx, "posts/show.iwai", post_detail_view(store, ctx, post; error = "Comment body is required."))
        create_comment!(store; post_id = post.id, user_id = user.id, body = body)
        return redirect(ctx, "/post/" * string(post.id))
    end

    return app
end
