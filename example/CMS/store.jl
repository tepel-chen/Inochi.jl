using Dates
using LibPQ
using PostgresORM
using Random
using Tables

mutable struct CMSUser <: PostgresORM.IEntity
    id::Union{Missing,Int32}
    name::Union{Missing,String}
    email::Union{Missing,String}
    password::Union{Missing,String}
    role::Union{Missing,String}
    bio::Union{Missing,String}
    joined_at::Union{Missing,DateTime}

    CMSUser(args::NamedTuple) = CMSUser(; args...)
    CMSUser(; id = missing, name = missing, email = missing, password = missing, role = missing, bio = missing, joined_at = missing) = begin
        x = new(missing, missing, missing, missing, missing, missing, missing)
        x.id = id
        x.name = name
        x.email = email
        x.password = password
        x.role = role
        x.bio = bio
        x.joined_at = joined_at
        x
    end
end

mutable struct CMSPost <: PostgresORM.IEntity
    id::Union{Missing,Int32}
    author_id::Union{Missing,Int32}
    title::Union{Missing,String}
    slug::Union{Missing,String}
    summary::Union{Missing,String}
    markdown::Union{Missing,String}
    published::Union{Missing,Bool}
    views::Union{Missing,Int32}
    created_at::Union{Missing,DateTime}
    updated_at::Union{Missing,DateTime}

    CMSPost(args::NamedTuple) = CMSPost(; args...)
    CMSPost(; id = missing, author_id = missing, title = missing, slug = missing, summary = missing, markdown = missing, published = missing, views = missing, created_at = missing, updated_at = missing) = begin
        x = new(missing, missing, missing, missing, missing, missing, missing, missing, missing, missing)
        x.id = id
        x.author_id = author_id
        x.title = title
        x.slug = slug
        x.summary = summary
        x.markdown = markdown
        x.published = published
        x.views = views
        x.created_at = created_at
        x.updated_at = updated_at
        x
    end
end

mutable struct CMSComment <: PostgresORM.IEntity
    id::Union{Missing,Int32}
    post_id::Union{Missing,Int32}
    user_id::Union{Missing,Int32}
    body::Union{Missing,String}
    created_at::Union{Missing,DateTime}

    CMSComment(args::NamedTuple) = CMSComment(; args...)
    CMSComment(; id = missing, post_id = missing, user_id = missing, body = missing, created_at = missing) = begin
        x = new(missing, missing, missing, missing, missing)
        x.id = id
        x.post_id = post_id
        x.user_id = user_id
        x.body = body
        x.created_at = created_at
        x
    end
end

mutable struct CMSFile <: PostgresORM.IEntity
    id::Union{Missing,Int32}
    owner_id::Union{Missing,Int32}
    filename::Union{Missing,String}
    media_type::Union{Missing,String}
    size_kb::Union{Missing,Int32}
    url::Union{Missing,String}
    uploaded_at::Union{Missing,DateTime}

    CMSFile(args::NamedTuple) = CMSFile(; args...)
    CMSFile(; id = missing, owner_id = missing, filename = missing, media_type = missing, size_kb = missing, url = missing, uploaded_at = missing) = begin
        x = new(missing, missing, missing, missing, missing, missing, missing)
        x.id = id
        x.owner_id = owner_id
        x.filename = filename
        x.media_type = media_type
        x.size_kb = size_kb
        x.url = url
        x.uploaded_at = uploaded_at
        x
    end
end

module CMSUserORM
using ..PostgresORM
data_type = Main.CMSUser
Main.PostgresORM.get_orm(x::Main.CMSUser) = CMSUserORM
get_table_name() = "public.cms_users"
const columns_selection_and_mapping = Dict(
    :id => "id",
    :name => "name",
    :email => "email",
    :password => "password",
    :role => "role",
    :bio => "bio",
    :joined_at => "joined_at",
)
get_id_props() = [:id]
const types_override = Dict()
const track_changes = false
end

module CMSPostORM
using ..PostgresORM
data_type = Main.CMSPost
Main.PostgresORM.get_orm(x::Main.CMSPost) = CMSPostORM
get_table_name() = "public.cms_posts"
const columns_selection_and_mapping = Dict(
    :id => "id",
    :author_id => "author_id",
    :title => "title",
    :slug => "slug",
    :summary => "summary",
    :markdown => "markdown",
    :published => "published",
    :views => "views",
    :created_at => "created_at",
    :updated_at => "updated_at",
)
get_id_props() = [:id]
const types_override = Dict()
const track_changes = false
end

module CMSCommentORM
using ..PostgresORM
data_type = Main.CMSComment
Main.PostgresORM.get_orm(x::Main.CMSComment) = CMSCommentORM
get_table_name() = "public.cms_comments"
const columns_selection_and_mapping = Dict(
    :id => "id",
    :post_id => "post_id",
    :user_id => "user_id",
    :body => "body",
    :created_at => "created_at",
)
get_id_props() = [:id]
const types_override = Dict()
const track_changes = false
end

module CMSFileORM
using ..PostgresORM
data_type = Main.CMSFile
Main.PostgresORM.get_orm(x::Main.CMSFile) = CMSFileORM
get_table_name() = "public.cms_files"
const columns_selection_and_mapping = Dict(
    :id => "id",
    :owner_id => "owner_id",
    :filename => "filename",
    :media_type => "media_type",
    :size_kb => "size_kb",
    :url => "url",
    :uploaded_at => "uploaded_at",
)
get_id_props() = [:id]
const types_override = Dict()
const track_changes = false
end

mutable struct CMSStore
    conninfo::String
end

slugify(text::AbstractString) = lowercase(replace(strip(String(text)), r"[^a-zA-Z0-9]+" => "-"))

to_db_int(value::Integer) = Int32(value)
maybe(value, default) = ismissing(value) ? default : value
is_admin(user::Union{Nothing,CMSUser}) = user !== nothing && user.role == "admin"

const ADMIN_PASSWORD_CHARS = collect("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")

function generate_password(length::Int = 20)::String
    rng = Random.RandomDevice()
    return String(rand(rng, ADMIN_PASSWORD_CHARS, length))
end

function db_conninfo()
    host = get(ENV, "DB_HOST", get(ENV, "POSTGRES_HOST", "db"))
    port = get(ENV, "DB_PORT", get(ENV, "POSTGRES_PORT", "5432"))
    dbname = get(ENV, "DB_NAME", get(ENV, "POSTGRES_DB", "cms"))
    user = get(ENV, "DB_USER", get(ENV, "POSTGRES_USER", "cms"))
    password = get(ENV, "DB_PASSWORD", get(ENV, "POSTGRES_PASSWORD", "cms"))
    return "host=$(host) port=$(port) dbname=$(dbname) user=$(user) password=$(password)"
end

function with_connection(f::Function, store::CMSStore)
    conn = LibPQ.Connection(store.conninfo; throw_error = true)
    try
        return f(conn)
    finally
        close(conn)
    end
end

function exec_sql!(conn::LibPQ.Connection, sql::AbstractString)
    result = LibPQ.execute(conn, String(sql); throw_error = true)
    close(result)
    return nothing
end

function query_entities(store::CMSStore, sql::AbstractString, ::Type{T}; args::Union{Missing,Vector} = missing) where {T <: PostgresORM.IEntity}
    with_connection(store) do conn
        return PostgresORM.execute_query_and_handle_result(String(sql), T, args, false, conn)
    end
end

function query_rows(store::CMSStore, sql::AbstractString; args::Union{Missing,Vector} = missing)
    with_connection(store) do conn
        result = ismissing(args) ? LibPQ.execute(conn, String(sql); throw_error = true) : LibPQ.execute(conn, String(sql), args; throw_error = true)
        try
            return collect(Tables.namedtupleiterator(result))
        finally
            close(result)
        end
    end
end

function query_scalar(store::CMSStore, sql::AbstractString; args::Union{Missing,Vector} = missing, default::Int = 0)::Int
    rows = query_rows(store, sql; args = args)
    isempty(rows) && return default
    row_values = collect(Base.values(rows[1]))
    isempty(row_values) && return default
    value = row_values[1]
    return Int(ismissing(value) ? default : value)
end

entity_or_nothing(entity) = ismissing(entity) ? nothing : entity

function wait_for_database(store::CMSStore; timeout_seconds::Int = 60)
    started = time()
    while true
        try
            with_connection(store) do conn
                result = LibPQ.execute(conn, "SELECT 1"; throw_error = true)
                close(result)
            end
            return nothing
        catch err
            (time() - started) >= timeout_seconds && rethrow(err)
            sleep(1.0)
        end
    end
end

function initialize_schema!(store::CMSStore)
    with_connection(store) do conn
        exec_sql!(conn, """
        CREATE TABLE IF NOT EXISTS public.cms_users (
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            role TEXT NOT NULL,
            bio TEXT NOT NULL DEFAULT '',
            joined_at TIMESTAMP NOT NULL DEFAULT NOW()
        )
        """)
        exec_sql!(conn, """
        CREATE TABLE IF NOT EXISTS public.cms_posts (
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            author_id INTEGER NOT NULL REFERENCES public.cms_users(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            slug TEXT NOT NULL,
            summary TEXT NOT NULL DEFAULT '',
            markdown TEXT NOT NULL DEFAULT '',
            published BOOLEAN NOT NULL DEFAULT TRUE,
            views INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP NOT NULL DEFAULT NOW()
        )
        """)
        exec_sql!(conn, "CREATE INDEX IF NOT EXISTS idx_cms_posts_author_id ON public.cms_posts(author_id)")
        exec_sql!(conn, """
        CREATE TABLE IF NOT EXISTS public.cms_comments (
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            post_id INTEGER NOT NULL REFERENCES public.cms_posts(id) ON DELETE CASCADE,
            user_id INTEGER NOT NULL REFERENCES public.cms_users(id) ON DELETE CASCADE,
            body TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        )
        """)
        exec_sql!(conn, "CREATE INDEX IF NOT EXISTS idx_cms_comments_post_id ON public.cms_comments(post_id)")
        exec_sql!(conn, """
        CREATE TABLE IF NOT EXISTS public.cms_files (
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            owner_id INTEGER NOT NULL REFERENCES public.cms_users(id) ON DELETE CASCADE,
            filename TEXT NOT NULL,
            media_type TEXT NOT NULL,
            size_kb INTEGER NOT NULL,
            url TEXT NOT NULL,
            uploaded_at TIMESTAMP NOT NULL DEFAULT NOW()
        )
        """)
        exec_sql!(conn, "CREATE INDEX IF NOT EXISTS idx_cms_files_owner_id ON public.cms_files(owner_id)")
    end
    return store
end

function create_user!(store::CMSStore; name::AbstractString, email::AbstractString, password::AbstractString, role::AbstractString = "member", bio::AbstractString = "")::CMSUser
    user = CMSUser(
        name = String(name),
        email = lowercase(String(email)),
        password = String(password),
        role = String(role),
        bio = String(bio),
    )
    with_connection(store) do conn
        PostgresORM.create_entity!(user, conn)
    end
    return user
end

function create_post!(store::CMSStore; author_id::Integer, title::AbstractString, summary::AbstractString, markdown::AbstractString, published::Bool = true)::CMSPost
    post = CMSPost(
        author_id = to_db_int(author_id),
        title = String(title),
        slug = slugify(title),
        summary = String(summary),
        markdown = String(markdown),
        published = published,
        views = Int32(0),
    )
    with_connection(store) do conn
        PostgresORM.create_entity!(post, conn)
    end
    return post
end

function update_post!(store::CMSStore, post::CMSPost; title::AbstractString, summary::AbstractString, markdown::AbstractString, published::Bool = true)::CMSPost
    post.title = String(title)
    post.slug = slugify(title)
    post.summary = String(summary)
    post.markdown = String(markdown)
    post.published = published
    post.updated_at = now()
    with_connection(store) do conn
        PostgresORM.update_entity!(post, conn)
    end
    return post
end

function create_comment!(store::CMSStore; post_id::Integer, user_id::Integer, body::AbstractString)::CMSComment
    comment = CMSComment(post_id = to_db_int(post_id), user_id = to_db_int(user_id), body = String(body))
    with_connection(store) do conn
        PostgresORM.create_entity!(comment, conn)
    end
    return comment
end

function create_file!(store::CMSStore; owner_id::Integer, filename::AbstractString, media_type::AbstractString, size_kb::Integer, url::AbstractString)::CMSFile
    file = CMSFile(
        owner_id = to_db_int(owner_id),
        filename = String(filename),
        media_type = String(media_type),
        size_kb = to_db_int(size_kb),
        url = String(url),
    )
    with_connection(store) do conn
        PostgresORM.create_entity!(file, conn)
    end
    return file
end

function list_users(store::CMSStore; limit::Integer = 20, offset::Integer = 0)
    query_entities(store, "SELECT * FROM public.cms_users ORDER BY joined_at DESC LIMIT \$1 OFFSET \$2", CMSUser; args = Any[to_db_int(limit), to_db_int(offset)])
end

function list_files(store::CMSStore; limit::Integer = 20, offset::Integer = 0)
    query_entities(store, "SELECT * FROM public.cms_files ORDER BY uploaded_at DESC LIMIT \$1 OFFSET \$2", CMSFile; args = Any[to_db_int(limit), to_db_int(offset)])
end

function list_all_posts(store::CMSStore; limit::Union{Nothing,Integer} = nothing, offset::Integer = 0)
    if limit === nothing
        return query_entities(store, "SELECT * FROM public.cms_posts ORDER BY created_at DESC", CMSPost)
    end
    return query_entities(store, "SELECT * FROM public.cms_posts ORDER BY created_at DESC LIMIT \$1 OFFSET \$2", CMSPost; args = Any[to_db_int(limit), to_db_int(offset)])
end

function list_public_posts(store::CMSStore; limit::Integer = 10, offset::Integer = 0)
    query_entities(store, "SELECT * FROM public.cms_posts WHERE published = true ORDER BY created_at DESC LIMIT \$1 OFFSET \$2", CMSPost; args = Any[to_db_int(limit), to_db_int(offset)])
end

function list_posts_by_author(store::CMSStore, user_id::Integer; limit::Integer = 10, offset::Integer = 0)
    query_entities(store, "SELECT * FROM public.cms_posts WHERE author_id = \$1 ORDER BY created_at DESC LIMIT \$2 OFFSET \$3", CMSPost; args = Any[to_db_int(user_id), to_db_int(limit), to_db_int(offset)])
end

function comments_for_post(store::CMSStore, post_id::Integer; limit::Integer = 20, offset::Integer = 0)
    query_entities(store, "SELECT * FROM public.cms_comments WHERE post_id = \$1 ORDER BY created_at ASC LIMIT \$2 OFFSET \$3", CMSComment; args = Any[to_db_int(post_id), to_db_int(limit), to_db_int(offset)])
end

function find_user(store::CMSStore, id::Integer)
    with_connection(store) do conn
        return entity_or_nothing(PostgresORM.retrieve_one_entity(CMSUser(id = to_db_int(id)), false, conn))
    end
end

function find_user_by_email(store::CMSStore, email::AbstractString)
    with_connection(store) do conn
        return entity_or_nothing(PostgresORM.retrieve_one_entity(CMSUser(email = lowercase(String(email))), false, conn))
    end
end

find_admin_user(store::CMSStore) = find_user_by_email(store, "admin@example.com")

function find_post(store::CMSStore, id::Integer)
    with_connection(store) do conn
        return entity_or_nothing(PostgresORM.retrieve_one_entity(CMSPost(id = to_db_int(id)), false, conn))
    end
end

function find_file(store::CMSStore, id::Integer)
    with_connection(store) do conn
        return entity_or_nothing(PostgresORM.retrieve_one_entity(CMSFile(id = to_db_int(id)), false, conn))
    end
end

function authenticate_user(store::CMSStore, email::AbstractString, password::AbstractString)
    user = find_user_by_email(store, email)
    user === nothing && return nothing
    return user.password == String(password) ? user : nothing
end

function increment_views!(store::CMSStore, post::CMSPost)
    post.views = Int32(maybe(post.views, 0) + 1)
    with_connection(store) do conn
        PostgresORM.update_entity!(post, conn)
    end
    return post
end

count_users(store::CMSStore) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_users")
count_files(store::CMSStore) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_files")
count_posts(store::CMSStore) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_posts")
count_comments(store::CMSStore) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_comments")
count_public_posts(store::CMSStore) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_posts WHERE published = true")
count_comments_for_post(store::CMSStore, post_id::Integer) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_comments WHERE post_id = \$1"; args = Any[to_db_int(post_id)])
count_posts_by_author(store::CMSStore, user_id::Integer) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_posts WHERE author_id = \$1"; args = Any[to_db_int(user_id)])
count_comments_by_user(store::CMSStore, user_id::Integer) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_comments WHERE user_id = \$1"; args = Any[to_db_int(user_id)])
count_published_posts(store::CMSStore) = query_scalar(store, "SELECT COUNT(*) AS count FROM public.cms_posts WHERE published = true")
count_total_views(store::CMSStore) = query_scalar(store, "SELECT COALESCE(SUM(views), 0) AS count FROM public.cms_posts")

function recent_post_stats(store::CMSStore; limit::Integer = 6)
    rows = NamedTuple[]
    for post in list_all_posts(store; limit = limit, offset = 0)
        comment_count = count_comments_for_post(store, Int(post.id))
        push!(rows, (
            id = Int(post.id),
            title = String(post.title),
            views = Int(maybe(post.views, 0)),
            comments = comment_count,
            view_bar = min(Int(maybe(post.views, 0)) * 8 + 20, 240),
            comment_bar = min(comment_count * 32 + 20, 240),
        ))
    end
    return rows
end

function seed_store!(store::CMSStore)
    count_users(store) > 0 && return store

    admin_password = generate_password()
    admin = create_user!(
        store;
        name = "Aiko Editor",
        email = "admin@example.com",
        password = admin_password,
        role = "admin",
        bio = "Editor-in-chief. Loves dashboards and structured content.",
    )
    writer = create_user!(
        store;
        name = "Ren Writer",
        email = "ren@example.com",
        password = "password",
        role = "member",
        bio = "Writes product essays, changelogs, and community updates.",
    )
    viewer = create_user!(
        store;
        name = "Mina Reader",
        email = "mina@example.com",
        password = "password",
        role = "member",
        bio = "Leaves thoughtful comments and catches wording problems.",
    )

    post1 = create_post!(
        store;
        author_id = Int(admin.id),
        title = "Designing a faster Julia CMS",
        summary = "Notes from rebuilding the stack around Inochi and IwaiEngine.",
        markdown = """
# Designing a faster Julia CMS

The goal is not only to render quickly, but to keep the authoring workflow clean.

## Principles

- Small route handlers
- Strong view models
- Templates that stay readable
""",
    )
    post1.views = Int32(148)
    with_connection(store) do conn
        PostgresORM.update_entity!(post1, conn)
    end

    post2 = create_post!(
        store;
        author_id = Int(writer.id),
        title = "Release process without fear",
        summary = "How to keep deploys boring while moving quickly.",
        markdown = """
# Release process without fear

Shipping is easier when the system has sharp defaults.

## Checklist

- write the migration plan
- note the rollback path
- benchmark the hot routes
""",
    )
    post2.views = Int32(92)
    with_connection(store) do conn
        PostgresORM.update_entity!(post2, conn)
    end

    draft = create_post!(
        store;
        author_id = Int(admin.id),
        title = "Admin IA draft",
        summary = "Rough ideas for the file browser and analytics layout.",
        markdown = """
# Admin IA draft

This draft is intentionally incomplete. It exists to demonstrate the editor screen.
""",
        published = false,
    )
    draft.views = Int32(17)
    with_connection(store) do conn
        PostgresORM.update_entity!(draft, conn)
    end

    create_comment!(store; post_id = Int(post1.id), user_id = Int(viewer.id), body = "The split between router and renderer reads very cleanly.")
    create_comment!(store; post_id = Int(post1.id), user_id = Int(writer.id), body = "Would like to see a draft preview mode next.")
    create_comment!(store; post_id = Int(post2.id), user_id = Int(admin.id), body = "The rollback checklist is the most important part here.")

    create_file!(store; owner_id = Int(admin.id), filename = "hero-architecture.png", media_type = "image/png", size_kb = 384, url = "/static/cms-hero.svg")
    create_file!(store; owner_id = Int(writer.id), filename = "launch-plan.pdf", media_type = "application/pdf", size_kb = 220, url = "/static/cms-sheet.svg")

    return store
end

function log_seed_credentials(store::CMSStore)
    admin = find_admin_user(store)
    admin === nothing && return nothing
    println("Admin login: admin@example.com / $(admin.password)")
    return nothing
end

function build_seed_store()::CMSStore
    store = CMSStore(db_conninfo())
    wait_for_database(store)
    initialize_schema!(store)
    seed_store!(store)
    log_seed_credentials(store)
    return store
end
