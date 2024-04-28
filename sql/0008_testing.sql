create table api.todos (
  id serial primary key,
  done boolean not null default false,
  task text not null,
  due timestamptz
);

insert into api.todos (task) values ('push to pre-prod testing'), ('pat self on back'), ('pat self on back again');

grant select, update on api.todos to web_anon, web_user;

