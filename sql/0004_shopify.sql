create schema if not exists shopify;

create table shopify.shop (
    shop text primary key,
    access_token text
);

create or replace function api.shopify_auth(_hmac text, _host text, _shop text, _timestamp text)
returns "text/html" as $$
import requests
import hmac
import hashlib
import plpy

client_id = plpy.execute("select current_setting('shopify.app_client_id')")[0]['current_setting']
client_secret = plpy.execute("select current_setting('shopify.app_client_secret')")[0]['current_setting']

message = f"host={_host}&shop={_shop}&timestamp={_timestamp}"
calculated_hmac = hmac.new(client_secret.encode(), msg=message.encode(), digestmod=hashlib.sha256).hexdigest()

if _hmac != calculated_hmac:
    raise Exception('HMAC validation failed')

scopes = 'read_products,write_products'
redirect_uri = 'https://usb-opposition-michael-sonic.trycloudflare.com/rpc/callback'
state = 'nonce'

auth_url = f"https://{_shop}/admin/oauth/authorize?client_id={client_id}&scope={scopes}&redirect_uri={redirect_uri}&state={state}"

return f"<html><body><script>window.location.href='{auth_url}';</script></body></html>"
$$ language plpython3u;

create or replace function api.shopify_callback(_shop text, _code text)
returns "text/html" as $$
import requests
import plpy

client_id = plpy.execute("select current_setting('shopify.app_client_id')")[0]['current_setting']
client_secret = plpy.execute("select current_setting('shopify.app_client_secret')")[0]['current_setting']

response = requests.post(f"https://{_shop}/admin/oauth/access_token", json={
    "client_id": client_id,
    "client_secret": client_secret,
    "code": _code
})

if response.status_code == 200:
    access_token = response.json()['access_token']

    # Store the access token in the database
    plpy.execute(f"INSERT INTO shopify.shop (shop, access_token) VALUES ('{_shop}', '{access_token}') ON CONFLICT (shop) DO UPDATE SET access_token = '{access_token}'")

    return f"<html><body><script>window.location.href='/rpc/success';</script></body></html>"
else:
    return f"<html><body><script>window.location.href='/rpc/error';</script></body></html>"
$$ language plpython3u;

