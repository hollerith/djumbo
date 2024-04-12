create schema if not exists shopify;

create table shopify.shop (
    shop text primary key,
    access_token text not null
);

alter database postgres set shopify.app_client_id to 'your_client_id_here';
alter database postgres set shopify.app_client_secret to 'your_client_secret_here';
alter database postgres set shopify.redirect_uri to 'https://yourapp.com/rpc/callback';

create or replace function shopify.auth(shop text, state text)
returns text
language plpgsql
as $$
declare
    client_id text := current_setting('shopify.app_client_id');
    redirect_uri text := current_setting('shopify.redirect_uri');
    scopes text := 'read_products,write_orders';
    auth_url text;
begin
    auth_url := 'https://' || shop || '/admin/oauth/authorize?' ||
                'client_id=' || client_id || '&' ||
                'scope=' || scopes || '&' ||
                'redirect_uri=' || redirect_uri || '&' ||
                'state=' || state;
    return auth_url;
end
$$;

create or replace function shopify.callback(shop text, code text, hmac_received text, state text)
returns void
language plpython3u
as $$
import requests

client_id = plpy.execute("select current_setting('shopify.app_client_id')")[0]['current_setting']
client_secret = plpy.execute("select current_setting('shopify.app_client_secret')")[0]['current_setting']
response = requests.post(
    'https://' || shop || '/admin/oauth/access_token',
    data={
        'client_id': client_id,
        'client_secret': client_secret,
        'code': code
    }
)
access_token = response.json().get('access_token')
plpy.execute(
    "insert into shopify.shop(shop, access_token) values (%s, %s) on conflict (shop) do update set access_token = excluded.access_token",
    (shop, access_token)
)
$$;
