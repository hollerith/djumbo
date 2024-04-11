-- Ensure the necessary extensions are available
create extension if not exists pgcrypto;
create extension if not exists citext;

create schema api;

-- create roles
create role web_anon nologin;
create role web_user nologin;

create role authenticator noinherit login password 'mysecretpassword';

-- grant web_user role to the authenticator role to allow role switching
grant web_anon to authenticator;
grant web_user to authenticator;

-- create or ensure the 'auth' schema exists
create schema if not exists auth;

-- Create the users table with a user_id column
create table if not exists auth.users (
    user_id serial primary key,
    email   citext not null unique,
    pass    text not null check (length(pass) < 512),
    role    name not null default 'web_user' check (length(role) < 512)
);

-- Create the sessions table
create table if not exists auth.sessions (
    token text not null primary key default encode(gen_random_bytes(32), 'base64'),
    user_id integer not null references auth.users(user_id),
    created timestamptz not null default current_timestamp,
    expires timestamptz not null default current_timestamp + interval '15min'
);

grant usage on schema api to web_anon, web_user;
grant usage on schema auth to web_anon, web_user;

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
alter database postgres set app.jwt_secret to 'X8uTPczUMpS2sAm3zG30HHMkOZEXUpdV';

-- sign the token
create or replace function sign(payload json, secret text) returns text as $$
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
create or replace function auth.get_jwt_token(_email text, _pass text) returns text as $$
declare
    user_record auth.users%rowtype;

begin
    select * into user_record from auth.users where email = _email and pass = crypt(_pass, pass);
    if found then
        return sign(
            row_to_json(
                (select r
                   from (select user_record.email,
                                user_record.role,
                                extract(epoch from now())::integer + 3600 as exp) r)
            ),
            current_setting('app.jwt_secret')
        );
    else
        raise exception 'Invalid credentials';
    end if;
end;
$$ language plpgsql security definer;

-- function for user registration
create or replace function auth.register(_email text, _pass text) returns text as $$
begin
    -- Check if the email is already registered
    if exists(select 1 from auth.users where email = _email) then
        return 'Email already registered.';
    else
        -- Insert the new user into the auth.users table
        insert into auth.users(email, pass)
            values(_email, crypt(_pass, gen_salt('bf')));

        return 'Registration successful.';
    end if;
exception when unique_violation then
    return 'Email already registered.';
end;
$$ language plpgsql security definer;

-- grant execution permissions to web_anon role
grant execute on function auth.register(text, text) to web_anon;
grant execute on function auth.get_jwt_token(text, text) to web_anon;

-- Session Management alternative

-- Function to create a new session
create or replace function auth.create_session(_email text, _pass text)
returns text as $$
declare
    _token text;
begin
    insert into auth.sessions(user_id)
    select user_id
      from auth.users
     where email = _email and pass = crypt(_pass, pass)
    returning token into _token;

    return _token;
end;
$$ language plpgsql security definer;


-- Function to refresh a session
create or replace function auth.refresh_session(session_token text) returns void as $$
begin
    update auth.sessions
    set expires = default
    where token = session_token and expires > current_timestamp;
end;
$$ language plpgsql security definer;

-- Function to expire a session (logout)
create or replace function auth.expire_session(_token text) returns void as $$
begin
    update auth.sessions
    set expires = current_timestamp
    where token = expire_session._token;
end;
$$ language plpgsql security definer;

-- grant necessary permissions
grant execute on function auth.create_session(text, text) to web_anon;
grant execute on function auth.refresh_session(text) to web_user;
grant execute on function auth.expire_session(text) to web_user;

-- Function to authenticate based on session token
create or replace function auth.authenticate() returns text as $$
declare
    session_token text;
    session_user_id int;
begin
    -- Get the session_token from the cookies
    select current_setting('request.cookies', true)::json->>'session_token'
        into session_token;

    -- Proceed with the existing logic to validate the session token and set the user role
    select user_id
        into session_user_id
        from auth.sessions
        where token = session_token and expires > current_timestamp;

    if session_user_id is not null then
        set local role to web_user;
        perform set_config('auth.user_id', session_user_id::text, true);
    else
        set local role to web_anon;
        perform set_config('auth.user_id', '', true);
    end if;

    return session_token;
end;
$$ language plpgsql;

grant execute on function auth.authenticate to web_anon;
