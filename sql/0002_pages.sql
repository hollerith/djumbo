create domain "text/html" as text;

create extension plpython3u;

-- djumbo render jinja2
create or replace function api.render(template_name text, context json)
returns "text/html" language plpython3u as $$
import jinja2, json

template_loader = jinja2.FileSystemLoader(searchpath="/var/www/templates")
jinja_env = jinja2.Environment(loader=template_loader)
template = jinja_env.get_template(template_name)

html_content = template.render(json.loads(context))
return html_content
$$;

-- GET index
create or replace function api.index()
returns "text/html" language plpgsql as $$
declare
    context json;
begin
    context := json_build_object(
        'title', 'jinja2 djumbo',
        'headline', 'Welcome to Djumbo 0.01'
    );
    return api.render('index.html', context::json);
end;
$$;


-- GET welcome
create or replace function api.welcome()
returns "text/html" language plpgsql as $$
declare
    context json;
    activity json;
    user_tables json;
    user_session_info json;
begin
    -- Gather selected activity information
    select json_agg(row_to_json(t)) into activity
    from (
        select datid, datname, pid, usesysid, usename, application_name, client_addr, client_hostname
        from pg_stat_activity
    ) t;

    -- Gather selected user tables information, excluding n_tup* columns
    select json_agg(row_to_json(t)) into user_tables
    from (
        select schemaname, relname, seq_scan, idx_scan, idx_tup_fetch, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
        from pg_stat_user_tables
    ) t;

    -- Fetch the user session information using the auth.authenticate() function
    select auth.authenticate() into user_session_info;

    context := json_build_object(
        'current_user', current_user,
        'current_database', current_database(),
        'current_schema', current_schema(),
        'activity', activity,
        'user_tables', user_tables,
        'user_session_info', user_session_info
    );

    return api.render('welcome.html', context::json);
end;
$$;


-- GET register
create or replace function api.register()
returns "text/html" language plpgsql as $$
begin
    return api.render('register.html', '{}'::json);
end;
$$;

-- POST register
create or replace function api.register(_email text, _password text)
returns text language plpgsql as $$
declare
    result text;
begin
    select auth.register(_email, _password) into result;

    if result = 'Registration successful.' then
        perform set_config('response.headers', '[{"HX-Redirect": "/rpc/login"}]', false);
    end if;

    return result;
end;
$$ security definer;

-- GET login
create or replace function api.login()
returns "text/html" language plpgsql as $$
declare
    context json;
begin
    context := json_build_object('user_email', current_setting('request.jwt.claims', true)::json->>'email');
    return api.render('login.html', context);
end;
$$;

-- POST login
create or replace function api.login(_email text, _password text)
returns json language plpgsql as $$
declare
    token    text;
    cookie   text;
    redirect text;
    headers  text;
begin
    select auth.create_session(_email, _password) into token;

    if token is null then
        raise insufficient_privilege
            using detail = 'invalid credentials';
    end if;

    cookie := format('{"Set-Cookie": "session_token=%s; HttpOnly; Path=/; SameSite=Lax"}', token);
    redirect := '{"HX-Redirect": "/rpc/welcome"}';
    headers := format('[%s, %s]', cookie, redirect);
    perform set_config('response.headers', headers, true);

    return json_build_object('auth', token);
end;
$$ security definer;


-- GET logout
create or replace function api.logout() returns void as $$
    begin
        perform auth.expire_session(
            current_setting('request.cookie.session_token', true)
        );

        perform set_config('response.headers', '[{"Set-Cookie": "session_token=; Path=/"}, {"HX-Redirect": "/rpc/index"}]', true);
    end;
$$ language plpgsql;

grant execute on function api.logout to web_user;

-- Debugging function to print the result of the sign function
create or replace function api.debug() returns text as $$
begin
    return current_user;
end;
$$ language plpgsql;

grant execute on function api.render(text, json) to web_anon, web_user;

grant execute on function api.index() to web_anon, web_user;
grant execute on function api.register() to web_anon;
grant execute on function api.register(text, text) to web_anon;
grant execute on function api.login() to web_anon;
grant execute on function api.login(text, text) to web_anon;
grant execute on function api.logout() to web_user;
grant execute on function api.welcome() to web_user;
grant execute on function api.debug() to web_user;


