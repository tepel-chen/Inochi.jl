using Dates
using Markdown

const HOME_PAGE_SIZE = 8
const ADMIN_POSTS_PAGE_SIZE = 8
const ADMIN_USERS_PAGE_SIZE = 20
const ADMIN_FILES_PAGE_SIZE = 20
const POST_COMMENTS_PAGE_SIZE = 20
const USER_DETAIL_POSTS_PAGE_SIZE = 10

format_stamp(dt::DateTime) = Dates.format(dt, "yyyy-mm-dd HH:MM")

function markdown_html(markdown::AbstractString)::String
    return sprint(io -> show(io, MIME"text/html"(), Markdown.parse(String(markdown))))
end

function current_user(ctx)
    return get(ctx, :current_user, nothing)
end

function nav_link(href::AbstractString, label::AbstractString, active::Bool)
    return (href = String(href), label = String(label), class_name = active ? "nav-link is-active" : "nav-link")
end

function page_param(ctx, key::AbstractString = "page")::Int
    raw = get(reqquery(ctx), String(key), "1")
    value = try
        Base.parse(Int, String(raw))
    catch
        1
    end
    return max(value, 1)
end

function page_href(path::AbstractString, page::Int, key::AbstractString = "page")::String
    page <= 1 && return String(path)
    return String(path) * "?" * String(key) * "=" * string(page)
end

function pagination_view(path::AbstractString, page::Int, total_items::Int, per_page::Int; key::AbstractString = "page")
    total_pages = max(cld(max(total_items, 1), per_page), 1)
    current_page = min(page, total_pages)
    return (
        current_page = current_page,
        total_pages = total_pages,
        has_multiple_pages = total_pages > 1,
        has_prev = current_page > 1,
        has_next = current_page < total_pages,
        prev_href = page_href(path, current_page - 1, key),
        next_href = page_href(path, current_page + 1, key),
    )
end

function current_user_view(user::Union{Nothing,CMSUser})
    user === nothing && return (logged_in = false, is_admin = false, name = "", role = "", id = 0)
    return (logged_in = true, is_admin = is_admin(user), name = user.name, role = user.role, id = user.id)
end

function layout_data(ctx; title::AbstractString, section::AbstractString = "home", message::AbstractString = "")
    user = current_user(ctx)
    return (
        page_title = String(title),
        csrf_token = csrf_token(ctx),
        csp_nonce = String(get(ctx, :csp_nonce, "")),
        section = String(section),
        message = String(message),
        has_message = !isempty(message),
        current_user = current_user_view(user),
        show_admin_nav = is_admin(user),
        nav_home = nav_link("/", "Home", section == "home"),
        nav_admin = nav_link("/admin/dashboard", "Admin", section == "admin"),
        nav_login = nav_link("/login", "Login", section == "login"),
        nav_register = nav_link("/register", "Register", section == "register"),
    )
end

function post_card_view(store::CMSStore, post::CMSPost)
    author = find_user(store, post.author_id)
    comment_count = count_comments_for_post(store, Int(post.id))
    return (
        id = post.id,
        title = post.title,
        summary = post.summary,
        href = "/post/" * string(post.id),
        slug = post.slug,
        author = author === nothing ? "Unknown" : author.name,
        created_at = format_stamp(post.created_at),
        updated_at = format_stamp(post.updated_at),
        views = post.views,
        comments = comment_count,
        status = post.published ? "Published" : "Draft",
        status_class = post.published ? "status-pill is-published" : "status-pill is-draft",
    )
end

function home_view(store::CMSStore, ctx)
    page = page_param(ctx)
    total_posts = count_public_posts(store)
    offset = (page - 1) * HOME_PAGE_SIZE
    posts = post_card_view.(Ref(store), list_public_posts(store; limit = HOME_PAGE_SIZE, offset = offset))
    return merge(layout_data(ctx; title = "Inochi CMS", section = "home"), (
        posts = posts,
        has_posts = !isempty(posts),
        show_new_post = is_admin(current_user(ctx)),
        pagination = pagination_view("/", page, total_posts, HOME_PAGE_SIZE),
    ))
end

function auth_view(ctx, mode::AbstractString; error::AbstractString = "")
    return merge(layout_data(ctx; title = uppercasefirst(String(mode)), section = String(mode), message = error), (
        mode = String(mode),
        form_title = mode == "login" ? "Welcome back" : "Create your account",
        form_action = "/" * String(mode),
        show_error = !isempty(error),
        error = String(error),
    ))
end

function comment_view(store::CMSStore, comment::CMSComment)
    user = find_user(store, comment.user_id)
    return (
        id = comment.id,
        body = comment.body,
        author = user === nothing ? "Unknown" : user.name,
        created_at = format_stamp(comment.created_at),
    )
end

function post_detail_view(store::CMSStore, ctx, post::CMSPost; error::AbstractString = "")
    page = page_param(ctx)
    total_comments = count_comments_for_post(store, Int(post.id))
    offset = (page - 1) * POST_COMMENTS_PAGE_SIZE
    comments = comment_view.(Ref(store), comments_for_post(store, post.id; limit = POST_COMMENTS_PAGE_SIZE, offset = offset))
    user = current_user(ctx)
    return merge(layout_data(ctx; title = post.title, section = "home", message = error), (
        post = (
            id = post.id,
            title = post.title,
            summary = post.summary,
            body_html = markdown_html(post.markdown),
            created_at = format_stamp(post.created_at),
            updated_at = format_stamp(post.updated_at),
            views = post.views,
            is_published = post.published,
        ),
        author = current_user_view(find_user(store, post.author_id)),
        comments = comments,
        has_comments = !isempty(comments),
        can_comment = user !== nothing,
        comment_action = "/post/" * string(post.id) * "/comments",
        comments_pagination = pagination_view("/post/" * string(post.id), page, total_comments, POST_COMMENTS_PAGE_SIZE),
        show_error = !isempty(error),
    ))
end

function admin_dashboard_view(store::CMSStore, ctx)
    cards = (
        posts = count_posts(store),
        published = count_published_posts(store),
        comments = count_comments(store),
        views = count_total_views(store),
    )
    return merge(layout_data(ctx; title = "Admin Dashboard", section = "admin"), (
        stats = cards,
        rows = recent_post_stats(store),
        has_rows = cards.posts > 0,
    ))
end

function admin_posts_view(store::CMSStore, ctx)
    user = current_user(ctx)
    user === nothing && return merge(layout_data(ctx; title = "Your Posts", section = "admin"), (posts = NamedTuple[], has_posts = false))
    page = page_param(ctx)
    total_posts = count_posts_by_author(store, Int(user.id))
    offset = (page - 1) * ADMIN_POSTS_PAGE_SIZE
    posts = post_card_view.(Ref(store), list_posts_by_author(store, user.id; limit = ADMIN_POSTS_PAGE_SIZE, offset = offset))
    return merge(layout_data(ctx; title = "Your Posts", section = "admin"), (
        posts = posts,
        has_posts = !isempty(posts),
        current_user_name = user.name,
        pagination = pagination_view("/admin/posts", page, total_posts, ADMIN_POSTS_PAGE_SIZE),
    ))
end

function admin_post_detail_view(store::CMSStore, ctx, post::CMSPost)
    author = find_user(store, post.author_id)
    comment_count = count_comments_for_post(store, Int(post.id))
    return merge(layout_data(ctx; title = "Post Detail", section = "admin"), (
        post = (
            id = post.id,
            title = post.title,
            slug = post.slug,
            summary = post.summary,
            body_html = markdown_html(post.markdown),
            created_at = format_stamp(post.created_at),
            updated_at = format_stamp(post.updated_at),
            views = post.views,
            comments = comment_count,
            status = post.published ? "Published" : "Draft",
        ),
        author_name = author === nothing ? "Unknown" : author.name,
    ))
end

function admin_post_editor_view(store::CMSStore, ctx, post::Union{Nothing,CMSPost}; error::AbstractString = "")
    is_new = post === nothing
    title = is_new ? "New Post" : "Edit Post"
    action = is_new ? "/admin/posts/new" : "/admin/posts/" * string(post.id) * "/update"
    return merge(layout_data(ctx; title = title, section = "admin", message = error), (
        title = title,
        is_new = is_new,
        action = action,
        upload_url = "/admin/posts/image-upload",
        post = (
            id = is_new ? 0 : post.id,
            title = is_new ? "" : post.title,
            summary = is_new ? "" : post.summary,
            markdown = is_new ? "# New draft\n\nStart writing..." : post.markdown,
            checked = is_new ? true : post.published,
        ),
    ))
end

function admin_users_view(store::CMSStore, ctx)
    page = page_param(ctx)
    total_users = count_users(store)
    offset = (page - 1) * ADMIN_USERS_PAGE_SIZE
    users = [(
        id = user.id,
        name = user.name,
        email = user.email,
        role = user.role,
        joined_at = format_stamp(user.joined_at),
        posts = count_posts_by_author(store, Int(user.id)),
        comments = count_comments_by_user(store, Int(user.id)),
    ) for user in list_users(store; limit = ADMIN_USERS_PAGE_SIZE, offset = offset)]
    return merge(layout_data(ctx; title = "Users", section = "admin"), (
        users = users,
        has_users = !isempty(users),
        pagination = pagination_view("/admin/users", page, total_users, ADMIN_USERS_PAGE_SIZE),
    ))
end

function admin_user_detail_view(store::CMSStore, ctx, user::CMSUser)
    page = page_param(ctx)
    total_posts = count_posts_by_author(store, Int(user.id))
    offset = (page - 1) * USER_DETAIL_POSTS_PAGE_SIZE
    posts = post_card_view.(Ref(store), list_posts_by_author(store, user.id; limit = USER_DETAIL_POSTS_PAGE_SIZE, offset = offset))
    return merge(layout_data(ctx; title = "User Detail", section = "admin"), (
        user = (
            id = user.id,
            name = user.name,
            email = user.email,
            role = user.role,
            bio = user.bio,
            joined_at = format_stamp(user.joined_at),
            posts = length(posts),
            comments = count_comments_by_user(store, Int(user.id)),
        ),
        posts = posts,
        has_posts = !isempty(posts),
        posts_pagination = pagination_view("/admin/users/" * string(user.id) * "/detail", page, total_posts, USER_DETAIL_POSTS_PAGE_SIZE),
    ))
end

function admin_files_view(store::CMSStore, ctx)
    page = page_param(ctx)
    total_files = count_files(store)
    offset = (page - 1) * ADMIN_FILES_PAGE_SIZE
    files = [(
        id = file.id,
        filename = file.filename,
        media_type = file.media_type,
        size_kb = file.size_kb,
        url = file.url,
        uploaded_at = format_stamp(file.uploaded_at),
        owner_name = something(find_user(store, file.owner_id), nothing) === nothing ? "Unknown" : find_user(store, file.owner_id).name,
    ) for file in list_files(store; limit = ADMIN_FILES_PAGE_SIZE, offset = offset)]
    return merge(layout_data(ctx; title = "Files", section = "admin"), (
        files = files,
        has_files = !isempty(files),
        pagination = pagination_view("/admin/files", page, total_files, ADMIN_FILES_PAGE_SIZE),
    ))
end

function admin_file_detail_view(store::CMSStore, ctx, file::CMSFile)
    owner = find_user(store, file.owner_id)
    return merge(layout_data(ctx; title = "File Detail", section = "admin"), (
        file = (
            id = file.id,
            filename = file.filename,
            media_type = file.media_type,
            size_kb = file.size_kb,
            url = file.url,
            uploaded_at = format_stamp(file.uploaded_at),
        ),
        owner_name = owner === nothing ? "Unknown" : owner.name,
    ))
end
