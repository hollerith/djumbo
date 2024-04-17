-- Ensure the necessary extensions are available
create extension if not exists pgcrypto;
create extension if not exists citext;

-- create roles
create role api nologin;
create role web_anon nologin;
create role web_user nologin;

create role authenticator noinherit login password 'mysecretpassword';

-- grant web_user role to the authenticator role to allow role switching
grant web_anon to authenticator;
grant web_user to authenticator;

-- create or ensure the 'api' schema exists
create schema authorization api;

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

alter default privileges revoke execute on functions from public;
alter default privileges for role api revoke execute on functions from public;

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

grant select on auth.users to web_anon, web_user;

-- Function to authenticate based on session token and return user record
create or replace function auth.authenticate() returns json as $$
declare
    session_token text;
    user_record json;
begin
    -- Get the session_token from the cookies
    select current_setting('request.cookies', true)::json->>'session_token'
        into session_token;

    -- Directly join auth.sessions with auth.users and select the user record into JSON
    select row_to_json(u) into user_record
    from auth.sessions s
    join auth.users u on s.user_id = u.user_id
    where s.token = session_token and s.expires > current_timestamp;

    -- If a user record is found, set the local role to web_user and configure the user ID
    if user_record is not null then
        set local role to web_user;
        perform set_config('auth.user_id', (user_record->>'user_id')::text, true);
    else
        set local role to web_anon;
        perform set_config('auth.user_id', '', true);
    end if;

    return user_record;
end;
$$ language plpgsql;

-- grant necessary permissions
grant execute on function auth.register(text, text) to web_anon;
grant execute on function auth.create_session(text, text) to web_anon;
grant execute on function auth.refresh_session(text) to web_user;
grant execute on function auth.expire_session(text) to web_user;
grant execute on function auth.authenticate() to web_anon, web_user;

grant select, insert on auth.sessions to web_anon;
grant select, update on auth.sessions to web_user;

-- extra reload pgrst

-- watch create and alter
create or replace function pgrst_ddl_watch() returns event_trigger as $$
declare
    cmd record;
begin
    for cmd in select * from pg_event_trigger_ddl_commands()
    loop
        if cmd.command_tag in (
        'create schema', 'alter schema'
        , 'create table', 'create table as', 'select into', 'alter table'
        , 'create foreign table', 'alter foreign table'
        , 'create view', 'alter view'
        , 'create materialized view', 'alter materialized view'
        , 'create function', 'alter function'
        , 'create trigger'
        , 'create type', 'alter type'
        , 'create rule'
        , 'comment'
        )
        -- don't notify in case of create temp table or other objects created on pg_temp
        and cmd.schema_name is distinct from 'pg_temp'
        then
            notify pgrst, 'reload schema';
        end if;
    end loop;
end; $$ language plpgsql;

-- watch drop
create or replace function pgrst_drop_watch() returns event_trigger as $$
declare
    obj record;
begin
    for obj in select * from pg_event_trigger_dropped_objects()
    loop
        if obj.object_type in (
        'schema'
        , 'table'
        , 'foreign table'
        , 'view'
        , 'materialized view'
        , 'function'
        , 'trigger'
        , 'type'
        , 'rule'
        )
        and obj.is_temporary is false -- no pg_temp objects
        then
            notify pgrst, 'reload schema';
        end if;
    end loop;
end; $$ language plpgsql;

create event trigger pgrst_ddl_watch on ddl_command_end execute procedure pgrst_ddl_watch();
create event trigger pgrst_drop_watch on sql_drop execute procedure pgrst_drop_watch();
