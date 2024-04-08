create schema api;
create role web_anon nologin;

grant usage on schema api to web_anon;
grant usage on schema auth to web_anon;

create role authenticator noinherit login password 'mysecretpassword';
grant web_anon to authenticator;

create domain "text/html" as text;

create extension plpython3u;

create or replace function api.index()
returns "text/html" as $$
import jinja2

template_loader = jinja2.FileSystemLoader(searchpath="/var/www/templates")
jinja_env = jinja2.Environment(loader=template_loader)
template = jinja_env.get_template('index.html')

data = {
  "title": "jinja2 djumbo", "headline": "your dynamic content here"
}

html_content = template.render(data)
return html_content
$$ language plpython3u;

create schema auth;
grant usage on schema auth to web_anon;

create or replace function auth.check_token() returns void
  language plpgsql
  as $$
begin
  if current_setting('request.jwt.claims', true)::json->>'email' =
     'disgruntled@mycompany.com' then
    raise insufficient_privilege
      using hint = 'Nope, we are on to you';
  end if;
end
$$;

-- create roles
create role web_anon nologin;
create role web_user nologin;

-- grant web_user role to the authenticator role to allow role switching
grant web_user to authenticator;

-- ensure the pgcrypto extension is available for password encryption
create extension if not exists pgcrypto;

-- create or ensure the 'auth' schema exists
create schema if not exists auth;

-- create users table within 'auth' schema for storing user credentials
create table if not exists auth.users (
  email    text primary key check (email ~* '^.+@.+\..+$'),
  pass     text not null check (length(pass) < 512),
  role     name not null default 'web_user' check (length(role) < 512)
);

-- password encryption function
create or replace function auth.encrypt_pass() returns trigger as $$
begin
  if tg_op = 'insert' or new.pass <> old.pass then
    new.pass = crypt(new.pass, gen_salt('bf'));
  end if;
  return new;
end;
$$ language plpgsql;

-- trigger for encrypting passwords
create trigger encrypt_pass before insert or update on auth.users
for each row execute procedure auth.encrypt_pass();

-- function for user registration
create or replace function auth.register(_email text, _password text)
returns text as $$
begin
  if exists(select 1 from auth.users where email = _email) then
    return 'Email already registered.';
  else
    insert into auth.users(email, pass) values (_email, crypt(_password, gen_salt('bf')));
    return 'Registration successful.';
  end if;
exception when unique_violation then
    return 'Email already registered.';
end;
$$ language plpgsql;

-- function for user login, returning a jwt token
create or replace function auth.login(_email text, _pass text) returns text as $$
declare
  jwt_token text;
begin
  if exists (select 1 from auth.users where email = _email and pass = crypt(_pass, pass)) then
    jwt_token := sign(
      row_to_json((select r from (select _email as email, extract(epoch from now())::integer + 3600 as exp) r)),
      current_setting('app.jwt_secret')
    );

    perform set_config('response.headers',
             '["Authorization: Bearer ' || jwt_token || '", "HX-Redirect: /rpc/index"]', true);

    return jwt_token;
  else
    raise exception 'Invalid credentials';
  end if;
end;
$$ language plpgsql security definer;

-- grant execution permissions to web_anon role
grant execute on function auth.register(text, text) to web_anon;
grant execute on function auth.login(text, text) to web_anon;

create or replace function api.registration()
returns "text/html" as $$
import jinja2

template_loader = jinja2.FileSystemLoader(searchpath="/var/www/templates")
jinja_env = jinja2.Environment(loader=template_loader)
template = jinja_env.get_template('register.html')

html_content = template.render()
return html_content
$$ language plpython3u;


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


create or replace function api.login()
returns "text/html" language plpython3u as $$
import jinja2

template_loader = jinja2.FileSystemLoader(searchpath="/var/www/templates")
jinja_env = jinja2.Environment(loader=template_loader)
template = jinja_env.get_template('login.html')

html_content = template.render()
return html_content
$$;

create or replace function api.login(_email text, _password text)
returns text language plpgsql as $$
declare
    result text;
begin
    select auth.login(_email, _password) into result;

    if result = 'Login successful.' then
        perform set_config('response.headers', '["HX-Redirect: /rpc/index"]', false);
    end if;

    return result;
end;
$$ security definer;
