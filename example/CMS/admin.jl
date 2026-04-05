using UUIDs

function parse_post_id(ctx)
    return try
        Base.parse(Int, ctx.params["id"])
    catch
        nothing
    end
end

const IMAGE_UPLOAD_DIR = joinpath(@__DIR__, "public", "uploads")
const IMAGE_UPLOAD_MIME_EXTENSIONS = Dict(
    "image/png" => "png",
    "image/jpeg" => "jpg",
    "image/jpg" => "jpg",
    "image/gif" => "gif",
    "image/webp" => "webp",
    "image/avif" => "avif",
    "image/svg+xml" => "svg",
    "image/bmp" => "bmp",
    "image/tiff" => "tiff",
    "image/x-icon" => "ico",
)

function normalized_mime_type(value::AbstractString)::String
    return lowercase(strip(split(String(value), ";"; limit = 2)[1]))
end

function upload_image_extension(content_type::AbstractString)
    return get(IMAGE_UPLOAD_MIME_EXTENSIONS, normalized_mime_type(content_type), nothing)
end

function upload_image_name(content_type::AbstractString)::String
    ext = upload_image_extension(content_type)
    ext === nothing && throw(ArgumentError("Unsupported image type: " * String(content_type)))
    return "upload-" * replace(string(uuid4()), "-" => "") * "." * ext
end

function save_uploaded_image!(store::CMSStore, ctx, part)
    user = current_user(ctx)
    user === nothing && return text(ctx, "Forbidden"; status = 403)

    content_type = normalized_mime_type(part.contenttype)
    startswith(content_type, "image/") || return text(ctx, "Unsupported image type"; status = 415)

    filename = upload_image_name(content_type)
    mkpath(IMAGE_UPLOAD_DIR)
    bytes = read(part)
    path = joinpath(IMAGE_UPLOAD_DIR, filename)
    open(path, "w") do io
        write(io, bytes)
    end

    file = create_file!(
        store;
        owner_id = user.id,
        filename = filename,
        media_type = content_type,
        size_kb = max(1, cld(length(bytes), 1024)),
        url = "/static/uploads/" * filename,
    )
    return json(ctx, (
        ok = true,
        file_id = file.id,
        url = file.url,
        markdown = "![](" * file.url * ")",
    ); status = 201)
end

function build_admin_app(store::CMSStore)::App
    app = App()
    use(app, require_admin())

    get(app, "/") do ctx
        redirect(ctx, "/admin/dashboard")
    end

    get(app, "/dashboard") do ctx
        render(ctx, "admin/dashboard.iwai", admin_dashboard_view(store, ctx))
    end

    get(app, "/posts") do ctx
        render(ctx, "admin/posts/index.iwai", admin_posts_view(store, ctx))
    end

    get(app, "/posts/new/edit") do ctx
        render(ctx, "admin/posts/edit.iwai", admin_post_editor_view(store, ctx, nothing))
    end

    post(app, "/posts/image-upload") do ctx
        try
            file_part = reqfile(ctx; name = "image")
            file_part === nothing && return text(ctx, "Image file is required"; status = 400)
            return save_uploaded_image!(store, ctx, file_part)
        catch err
            if err isa ArgumentError
                message = sprint(showerror, err)
                if occursin("max_content_size", message)
                    return text(ctx, "Payload too large"; status = 413)
                elseif occursin("multipart/form-data", message)
                    return text(ctx, "Expected multipart form data"; status = 400)
                elseif occursin("Unsupported image type", message)
                    return text(ctx, "Unsupported image type"; status = 415)
                end
            end
            println(stderr, "image upload failed")
            showerror(stderr, err, catch_backtrace())
            println(stderr)
            return text(ctx, "Internal Server Error"; status = 500)
        end
    end

    post(app, "/posts/new") do ctx
        user = current_user(ctx)
        form = reqform(ctx)
        title = strip(get(form, "title", ""))
        isempty(title) && return render(ctx, "admin/posts/edit.iwai", admin_post_editor_view(store, ctx, nothing; error = "Title is required."))
        post = create_post!(
            store;
            author_id = user.id,
            title = title,
            summary = strip(get(form, "summary", "")),
            markdown = get(form, "markdown", ""),
            published = get(form, "published", "") == "on",
        )
        return redirect(ctx, "/admin/posts/" * string(post.id) * "/detail")
    end

    get(app, "/posts/:id/detail") do ctx
        post_id = parse_post_id(ctx)
        post = post_id === nothing ? nothing : find_post(store, post_id)
        post === nothing && return text(ctx, "Post not found"; status = 404)
        return render(ctx, "admin/posts/detail.iwai", admin_post_detail_view(store, ctx, post))
    end

    get(app, "/posts/:id/edit") do ctx
        post_id = parse_post_id(ctx)
        post = post_id === nothing ? nothing : find_post(store, post_id)
        post === nothing && return text(ctx, "Post not found"; status = 404)
        return render(ctx, "admin/posts/edit.iwai", admin_post_editor_view(store, ctx, post))
    end

    post(app, "/posts/:id/update") do ctx
        post_id = parse_post_id(ctx)
        post = post_id === nothing ? nothing : find_post(store, post_id)
        post === nothing && return text(ctx, "Post not found"; status = 404)
        form = reqform(ctx)
        title = strip(get(form, "title", ""))
        isempty(title) && return render(ctx, "admin/posts/edit.iwai", admin_post_editor_view(store, ctx, post; error = "Title is required."))
        update_post!(
            store,
            post;
            title = title,
            summary = strip(get(form, "summary", "")),
            markdown = get(form, "markdown", ""),
            published = get(form, "published", "") == "on",
        )
        return redirect(ctx, "/admin/posts/" * string(post.id) * "/detail")
    end

    get(app, "/users") do ctx
        render(ctx, "admin/users/index.iwai", admin_users_view(store, ctx))
    end

    get(app, "/users/:id/detail") do ctx
        user_id = parse_post_id(ctx)
        user = user_id === nothing ? nothing : find_user(store, user_id)
        user === nothing && return text(ctx, "User not found"; status = 404)
        return render(ctx, "admin/users/detail.iwai", admin_user_detail_view(store, ctx, user))
    end

    get(app, "/files") do ctx
        render(ctx, "admin/files/index.iwai", admin_files_view(store, ctx))
    end

    get(app, "/files/:id/detail") do ctx
        file_id = parse_post_id(ctx)
        file = file_id === nothing ? nothing : find_file(store, file_id)
        file === nothing && return text(ctx, "File not found"; status = 404)
        return render(ctx, "admin/files/detail.iwai", admin_file_detail_view(store, ctx, file))
    end

    return app
end
