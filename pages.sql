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
    session_token text;
begin

    -- Prepare the context as a JSON object
    context := json_build_object(
        'user_email', current_setting('request.jwt.claims', true)::json->>'email',
        'current_user', current_user,
        'current_timestamp', current_timestamp,
        'session_token', session_token
    );

    -- Directly return the result of api.render
    return api.render('welcome.html', context);
end;
$$;

-- GET register
create or replace function api.register()
returns "text/html" language plpgsql as $$
begin
    -- Call api.render with 'register.html' and an empty JSON object for context
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
    token text;
begin
    select auth.create_session(_email, _password) into token;

    if token is null then
        raise insufficient_privilege
            using detail = 'invalid credentials';
    end if;

    perform set_config('response.headers',
      '[{"Set-Cookie": "session_token=' || token ||
      '; HttpOnly; Path=/; SameSite=Lax"},' ||
      ' {"HX-Redirect": "/rpc/welcome"}]', true);

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
declare
    info text;
begin
    select current_user
        || ' '
        || current_setting('app.jwt_secret')
        || ' '
        || sign('{"email": "admin@nowhere.com", "role": "web_user", "exp": 1712718168}', 'X8uTPczUMpS2sAm3zG30HHMkOZEXUpdV')
      into info;
    return info;
end;
$$ language plpgsql;
