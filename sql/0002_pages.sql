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


-- djumbo markdown mistletoe
create or replace function api.markdown(template_name text, context json)
returns "text/html" language plpython3u as $$
import json
import jinja2 as j2
import mistletoe as md

template = """
{% extends 'base.html' %}
{% block content %}
<div class='markdown'>
    {{ html_content | safe }}
</div>
{% endblock %}
"""

template_path = f"/var/www/pages/{template_name}".replace('../','')
try:
    with open(template_path, 'r') as file:
        markdown_content = file.read()
    html_content = md.markdown(markdown_content)
except Exception as e:
    raise plpy.Error(f'Markdown processing failed: {str(e)}')

try:
    jinja_env = j2.Environment(loader=j2.FileSystemLoader('/var/www/templates'))
    jinja_template = jinja_env.from_string(template)

    context_json = json.loads(context)
    context_json['html_content'] = html_content
    rendered_html = jinja_template.render(context_json)
except Exception as e:
    raise plpy.Error(f'Template rendering failed: error {str(e)}')

return rendered_html
$$;


-- GET index
create or replace function api.index()
returns "text/html" language plpgsql as $$
declare
    context json;
    login json;
begin
    select auth.authenticate() into login;

    context := json_build_object(
        'title', 'jinja2 djumbo',
        'headline', 'Welcome to Djumbo 0.10',
        'login', login
    );

    return api.render('index.html', context::json);
end;
$$;

create or replace function api.error(code integer default 404)
returns "text/html" language plpgsql as $$
declare
    context json;
begin
    case code
        when 404 then
            context := json_build_object(
                'title', 'Page not found',
                'message', 'The page you are looking for is temporarily unavailable.',
                'code', code
            );
        when 400 then
            context := json_build_object(
                'title', 'Bad request',
                'message', 'Your browser sent a request that this server could not understand.',
                'code', code
            );
        when 500 then
            context := json_build_object(
                'title', 'Server fault',
                'message', 'An internal server error occurred.',
                'code', code
            );
        else
            context := json_build_object(
                'title', 'Unexpected error',
                'message', 'An unexpected error, probably DNS, has occurred.',
                'code', code
            );
    end case;

    return api.render('error.html', context);
end;
$$;


-- GET welcome
create or replace function api.welcome()
returns "text/html" language plpgsql as $$
declare
    context json;
    activity json;
    user_tables json;
    login json;
begin
    -- Gather selected activity information
    select json_agg(row_to_json(t)) into activity
    from (
        select datid, datname, pid, usesysid, usename, application_name, client_addr, client_hostname
        from pg_stat_activity where datid is not null limit 10
    ) t;

    -- Gather selected user tables information, excluding n_tup* columns
    select json_agg(row_to_json(t)) into user_tables
    from (
        select schemaname, relname, seq_scan, idx_scan, idx_tup_fetch, last_autovacuum, last_autoanalyze
        from pg_stat_user_tables
    ) t;

    -- Fetch the user session information using the auth.authenticate() function
    select auth.authenticate() into login;

    context := json_build_object(
        'current_user', current_user,
        'current_database', current_database(),
        'current_schema', current_schema(),
        'activity', activity,
        'user_tables', user_tables,
        'login', login
    );

    return api.render('welcome.html', context::json);
end;
$$;

-- GET about
create or replace function api.about()
returns "text/html" language plpgsql as $$
declare
    context json;
    login json;
begin
    select auth.authenticate() into login;

    context := json_build_object(
        'title', 'Djumbo README.md',
        'login', login
    );

    return api.markdown('About.md', context::json);
end;
$$;

-- GET link
create or replace function api.link(page_name text)
returns "text/html" language plpgsql as $$
declare
    context json;
    login json;
begin
    select auth.authenticate() into login;

    context := json_build_object(
        'login', login
    );

    return api.markdown(page_name, context::json);
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
        perform set_config('response.headers', '[{"HX-Redirect": "/login"}]', false);
    end if;

    return result;
end;
$$ security definer;


-- GET login
create or replace function api.login()
returns "text/html" language plpgsql as $$
declare
    context json;
    redirect text := current_setting('request.header.x-original-status', true);
begin
    context := json_build_object();

    if redirect = '401' or redirect = '403' then
        context := jsonb_set(context, '{banner}', 'Your session expired. Please login again.');
        context := jsonb_set(context, '{title}', 'Session Expired');
    end if;

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
    redirect := '{"HX-Redirect": "/welcome"}';
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

        perform set_config('response.headers', '[{"Set-Cookie": "session_token=; Path=/"}, {"HX-Redirect": "/"}]', true);
    end;
$$ language plpgsql;

grant execute on function api.logout to web_user;


-- GET debug
create or replace function api.debug() returns text as $$
begin
    return current_user;
end;
$$ language plpgsql;


-- Permissions
grant execute on function api.render(text, json) to web_anon, web_user;
grant execute on function api.markdown(text, json) to web_anon, web_user;

grant execute on function api.index() to web_anon, web_user;
grant execute on function api.error(integer) to web_anon, web_user;
grant execute on function api.register() to web_anon;
grant execute on function api.register(text, text) to web_anon;
grant execute on function api.login() to web_anon;
grant execute on function api.login(text, text) to web_anon;
grant execute on function api.logout() to web_user;
grant execute on function api.welcome() to web_user;
grant execute on function api.about() to web_anon, web_user;
grant execute on function api.link(text) to web_anon, web_user;
grant execute on function api.debug() to web_user;
