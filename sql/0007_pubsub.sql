-- GET .well_known/finger
create or replace function api.finger(resource text) returns json as $$
declare
    context json;
    username text := substring(resource from '^([^@]+)');
    domain text := substring(resource from '@(.+)$');
    row_count int;
begin

    select json_build_object(
                'subject', resource,
                'links', json_agg(json_build_object(
                    'rel', 'self',
                    'type', 'application/activity+json',
                    'href', format('https://%s/%s', domain, username)
                ))
           ) into context
      from auth.users
     where email ~ format('^%s@', username)
     limit 1;

    return context::json;
end;
$$ language plpgsql;

grant execute on function api.finger(text) to web_anon, web_user;

create table api.profile (
    user_id int primary key references auth.users(user_id) on delete cascade,
    username text unique not null,
    display_name text,
    bio text,
    image_url text,
    banner_url text,
    public_key text,
    created_at timestamp without time zone default now(),
    updated_at timestamp without time zone default now()
);

-- Function matching the ActivityPub user profile endpoint
create or replace function api.users(username text) returns json as $$
declare
    profile_rec record;
begin
    select * into profile_rec from api.profile where username = lower(username) limit 1;

    if not found then
        raise exception 'Profile not found for %', username;
    end if;

    return json_build_object(
        '@context', 'https://www.w3.org/ns/activitystreams',
        'id', format('https://%s/users/%s', current_setting('app.domain'), profile_rec.username),
        'type', 'Person',
        'preferredUsername', profile_rec.username,
        'displayName', profile_rec.display_name,
        'summary', profile_rec.bio,
        'image', json_build_object(
            'type', 'Image',
            'mediaType', 'image/jpeg',
            'url', profile_rec.image_url
        ),
        'publicKey', json_build_object(
            'id', format('https://%s/users/%s#main-key', current_setting('app.domain'), profile_rec.username),
            'owner', format('https://%s/users/%s', current_setting('app.domain'), profile_rec.username),
            'publicKeyPem', profile_rec.public_key
        )
    );
end;
$$ language plpgsql stable security definer;
grant execute on function api.users(text) to web_anon;

-- GET account
create or replace function api.account() returns "text/html" as $$
declare
    user_profile json;
    login json;
begin
    select auth.authenticate() into login;

    select json_build_object(
        'username', p.username,
        'display_name', p.display_name,
        'bio', p.bio,
        'image_url', p.image_url,
        'banner_url', p.banner_url,
        'public_key', p.public_key
    ) into user_profile
    from api.profile p
    where p.user_id = (login->>'user_id')::int;

    return api.render('profile.html', json_build_object(
        'title', 'Edit Profile',
        'headline', 'Update your profile information',
        'login', login,
        'profile', user_profile
    )::json);
end;
$$ language plpgsql;

-- POST profile
create or replace function api.account(
    username text,
    display_name text,
    bio text,
    image_url text,
    banner_url text,
    public_key text
)
returns text language plpgsql as $$
declare
    login json;
begin
    select auth.authenticate() into login;

    insert into api.profile (user_id, username, display_name, bio, image_url, banner_url, public_key, updated_at)
    values ((login->>'user_id')::int, lower(username), display_name, bio, image_url, banner_url, public_key, now())
    on conflict (user_id) do update
    set
        username = excluded.username,
        display_name = excluded.display_name,
        bio = excluded.bio,
        image_url = excluded.image_url,
        banner_url = excluded.banner_url,
        public_key = excluded.public_key,
        updated_at = now();

    -- Render and return the profile update confirmation page
    return api.render('profile.html', json_build_object(
        'title', 'Profile Updated',
        'headline', 'Your profile has been updated successfully.',
        'login', login
    )::json);
end;
$$ stable security definer;

grant select, update, insert on api.profile to web_user;

grant execute on function api.account() to web_user;
grant execute on function api.account(text, text, text, text, text, text) to web_user;
