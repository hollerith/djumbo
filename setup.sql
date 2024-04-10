create schema api;
create role web_anon nologin;

grant usage on schema api to web_anon;
grant usage on schema auth to web_anon;

create role authenticator noinherit login password 'mysecretpassword';
grant web_anon to authenticator;

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

grant usage on schema auth to web_anon;

-- db preflight
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

alter database postgres set app.jwt_secret to 'mustbeatleastthirtytwocharacters';

select pg_reload_conf();
show app.jwt_secret;

-- sign the token
create or replace function sign(payload json, secret text)
returns text as $$
declare
    header text;
    payload_encoded text;
    signature text;
begin
    header := encode(convert_to('{"alg": "HS256","typ": "JWT"}', 'utf8'), 'base64');
    header := replace(replace(rtrim(header, '='), '+', '-'), '/', '_');

    payload_encoded := encode(convert_to(payload::text, 'utf8'), 'base64');
    payload_encoded := replace(replace(rtrim(payload_encoded, '='), '+', '-'), '/', '_');
    payload_encoded := replace(payload_encoded, E'\n', '');

    signature := encode(hmac(header || '.' || payload_encoded, secret, 'sha256'), 'base64');
    signature := replace(replace(rtrim(signature, '='), '+', '-'), '/', '_');

    return header || '.' || payload_encoded || '.' || signature;
end;
$$ language plpgsql volatile security definer;

-- function for user login, returning a jwt token
create or replace function auth.login(_email text, _pass text)
returns text language plpgsql security definer as $$
declare
 user_record auth.users%rowtype;

begin
    select * into user_record from auth.users where email = _email and pass = crypt(_pass, pass);
    if found then
        return sign(
            row_to_json((select r from (select user_record.email, user_record.role, extract(epoch from now())::integer + 3600 as exp) r)),
            current_setting('app.jwt_secret')
        );
    else
        raise exception 'Invalid credentials';
    end if;
end;
$$;

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

-- grant execution permissions to web_anon role
grant execute on function auth.register(text, text) to web_anon;
grant execute on function auth.login(text, text) to web_anon;
