function attach_current_user(store::CMSStore)
    return function(ctx, next)
        session = secure_cookie(ctx, "session"; default = nothing)
        if session !== nothing
            user_id = try
                Base.parse(Int, String(session))
            catch
                nothing
            end
            if user_id !== nothing
                user = find_user(store, user_id)
                user !== nothing && set!(ctx, :current_user, user)
            end
        end
        return next()
    end
end

function require_login()
    return function(ctx, next)
        current_user(ctx) === nothing && return redirect(ctx, "/login"; status = 303)
        return next()
    end
end

function require_admin()
    return function(ctx, next)
        user = current_user(ctx)
        user === nothing && return redirect(ctx, "/login"; status = 303)
        is_admin(user) || return text(ctx, "Forbidden"; status = 403)
        return next()
    end
end

function register_auth_routes!(app::App, store::CMSStore)::App
    get(app, "/login") do ctx
        ctx.render("auth/login.iwai", auth_view(ctx, "login"))
    end

    post(app, "/login") do ctx
        form = ctx.reqform()
        user = authenticate_user(store, get(form, "email", ""), get(form, "password", ""))
        user === nothing && return ctx.render("auth/login.iwai", auth_view(ctx, "login"; error = "Invalid email or password."))
        set_secure_cookie(ctx, "session", string(user.id); httponly = true, path = "/")
        return redirect(ctx, is_admin(user) ? "/admin/dashboard" : "/")
    end

    get(app, "/register") do ctx
        ctx.render("auth/register.iwai", auth_view(ctx, "register"))
    end

    post(app, "/register") do ctx
        form = ctx.reqform()
        email = strip(get(form, "email", ""))
        name = strip(get(form, "name", ""))
        password = get(form, "password", "")
        isempty(email) && return ctx.render("auth/register.iwai", auth_view(ctx, "register"; error = "Email is required."))
        isempty(name) && return ctx.render("auth/register.iwai", auth_view(ctx, "register"; error = "Name is required."))
        isempty(password) && return ctx.render("auth/register.iwai", auth_view(ctx, "register"; error = "Password is required."))
        find_user_by_email(store, email) !== nothing && return ctx.render("auth/register.iwai", auth_view(ctx, "register"; error = "Email already exists."))
        user = create_user!(store; name = name, email = email, password = password, role = "member", bio = "Freshly registered through the CMS example.")
        set_secure_cookie(ctx, "session", string(user.id); httponly = true, path = "/")
        return redirect(ctx, "/")
    end

    post(app, "/logout") do ctx
        ctx.setcookie("session", ""; path = "/", maxage = 0, httponly = true)
        redirect(ctx, "/")
    end

    return app
end
