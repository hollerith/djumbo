create extension if not exists hstore;
create extension if not exists pg_cron;

create unlogged table caching (
    id serial primary key,
    data hstore,
    created timestamp default now(),
    ttl int default 3600
);

insert into caching (data) values
    ('key1 => "value1", key2 => "value2"'),
    ('key3 => "value3", key4 => "value4"');

select cron.schedule('* * * * *', $$delete from caching where created + (ttl * interval '1 second') < now()$$);

/*create or replace function fetch_and_cache_new_github_repos()
returns void as $$
import requests
from datetime import datetime, timedelta

time_window_start = datetime.utcnow() - timedelta(minutes=5)
time_window_start_iso = time_window_start.strftime('%Y-%m-%dT%H:%M:%SZ')

token = plpy.execute("SELECT current_setting('app.pat') as token")[0]['token']

url = "https://api.github.com/search/repositories?q=created:>{}+fork:false&sort=created&order=asc".format(time_window_start_iso)
headers = {'Authorization': f'token {token}'}

response = requests.get(url, headers=headers)
if response.status_code == 200:
    repos = response.json()['items']
    plan = plpy.prepare("INSERT INTO caching (data, ttl) VALUES ($1::hstore, $2)", ["text", "integer"])
    for repo in repos:
        repo_data = "'url' => '{}', 'name' => '{}', 'language' => '{}'".format(repo['html_url'], repo['name'], repo['language'])
        plpy.execute(plan, [repo_data, 3600])
$$ language plpython3u;*/

-- alter database postgres set "app.pat" TO 'ghp_adboFAdeezNutz';
-- select cron.schedule('*/5 * * * *', 'select fetch_and_cache_new_github_repos()');

-- alter database postgres set "app.pat" TO 'ghp_adboFAdeezNutz';
-- select cron.schedule('*/5 * * * *', 'select fetch_and_cache_new_github_repos()');

--select fetch_and_cache_new_github_repos();

-- GET latest
create or replace function api.latest()
returns "text/html" language plpgsql as $$
declare
    repos_data json;
    login json;
begin
    select coalesce(json_agg(row_to_json(t)), '[]') into repos_data
    from (
        select id, data, created, ttl
        from public.caching
        order by created desc
    ) t;

    select auth.authenticate() into login;

    return api.render('latest.html', json_build_object(
        'current_user', current_user,
        'current_database', current_database(),
        'current_schema', current_schema(),
        'repos_data', repos_data,
        'login', login
    )::json);
end;
$$;

grant execute on function api.latest() to web_anon, web_user;
grant select on public.caching to web_anon, web_user;
