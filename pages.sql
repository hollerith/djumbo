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
    return api.render('index.html', context::text);
end;
$$;


-- GET welcome
create or replace function api.welcome()
returns "text/html" language plpgsql as $$
declare
    context json;
begin
    -- Prepare the context as a JSON object
    context := json_build_object('user_email', current_setting('request.jwt.claims', true)::json->>'email');

    -- Directly return the result of api.render
    return api.render('welcome.html', context);
end;
$$;

SELECT api.render('welcome.html', '{"name": "John", "email": "john@example.com"}'::json) AS rendered_html;

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
        perform set_config('response.headers', '["HX-Redirect: /rpc/login"]', false);
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

select api.login('admin@nowhere.com', 'P455w0rd!')

-- POST login
create or replace function api.login(_email text, _password text)
returns json language plpgsql as $$
declare
    jwt_token text;
begin
    select auth.login(_email, _password) into jwt_token;

    perform set_config('response.headers',
       '[{"Set-Cookie": "auth=' || jwt_token || '; HttpOnly; Path=/; SameSite=Lax"},' ||
       ' {"Authorization": "Bearer ' || jwt_token || '"},' ||
       ' {"HX-Redirect": "/rpc/welcome"}]', true);

    return json_build_object('auth', jwt_token);
end;
$$ security definer;
