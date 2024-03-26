-- first: https://postgrest.org/en/v12/tutorials/tut0.html 

grant all on api.todos to web_anon;
grant usage, select on sequence api.todos_id_seq to web_anon;

--create domain "text/html" as text;

create or replace function api.sanitize_html(text) returns text as $$
  select replace(replace(replace(replace(replace($1, '&', '&amp;'), '"', '&quot;'),'>', '&gt;'),'<', '&lt;'), '''', '&apos;')
$$ language sql;

create or replace function api.index() returns "text/html" as $$
select $html$
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>PostgREST + HTMX To-Do List</title>
    <script src="https://cdn.tailwindcss.com?plugins=forms,typography,aspect-ratio,line-clamp"></script>
    <script src="https://unpkg.com/htmx.org"></script>
  </head>
  <body class="bg-gray-900"
        hx-headers='{"Accept": "text/html"}'>
    <div class="flex justify-center">
      <div class="max-w-lg mt-5 p-6 bg-gray-800 border border-gray-800 rounded-lg shadow-xl">
        <h5 class="mb-3 text-2xl font-bold tracking-tight text-white">PostgREST + HTMX To-Do List</h5>
        <form hx-post="/rpc/add_todo"
              hx-target="#todo-list-area"
              hx-trigger="submit"
              hx-on="htmx:afterRequest: this.reset()">
          <input class="bg-gray-50 border text-sm rounded-lg block w-full p-2.5 mb-3 bg-gray-700 border-gray-600 placeholder-gray-400 text-white focus:ring-blue-500 focus:border-blue-500"
                 type="text" name="_task" placeholder="Add a todo...">
        </form>
        <div id="todo-list-area">
          $html$
            || api.html_all_todos() ||
          $html$
        <div>
      </div>
    </div>
  </body>
  </html>
  $html$;
$$ language sql;

create or replace function api.add_todo(_task text) returns "text/html" as $$
  insert into api.todos(task) values (_task);
  select api.html_all_todos();
$$ language sql;

create or replace function api.change_todo_state(_id int, _done boolean) returns "text/html" as $$
  update api.todos set done = _done where id = _id;
  select api.html_all_todos();
$$ language sql;

create or replace function api.change_todo_task(_id int, _task text) returns "text/html" as $$
  update api.todos set task = _task where id = _id;
  select api.html_all_todos();
$$ language sql;

create or replace function api.delete_todo(_id int) returns "text/html" as $$
  delete from api.todos where id = _id;
  select api.html_all_todos();
$$ language sql;

create or replace function api.html_all_todos() returns text as $$
  select coalesce(
    '<ul id="todo-list" role="list" class="divide-y divide-gray-700 text-gray-100">'
      || string_agg(api.html_todo(t), '' order by t.id) ||
    '</ul>',
    '<p class="text-gray-100">There is nothing else to do.</p>'
  )
  from api.todos t;
$$ language sql;

create or replace function api.html_todo(api.todos) returns text as $$
select format($html$
<li class="py-3">
  <div class="flex justify-between items-center">
    <div id="todo-edit-area-%1$s" class="pr-5">
      <form id="edit-task-state-%1$s"
            hx-post="/rpc/change_todo_state"
            hx-vals='{"_id": %1$s, "_done": %4$s}'
            hx-target="#todo-list-area"
            hx-trigger="click">
        <span class="ml-2 %2$s cursor-pointer">
          %3$s
        </span>
      </form>
    </div>
    <div>
      <button class="p-1.5 rounded-full hover:bg-gray-700 focus:ring-gray-800"
              hx-get="/rpc/html_editable_task"
              hx-vals='{"_id": "%1$s"}'
              hx-target="#todo-edit-area-%1$s"
              hx-trigger="click">
        <svg class="w-4 h-4 text-blue-300" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 20 18">
          <path d="M12.687 14.408a3.01 3.01 0 0 1-1.533.821l-3.566.713a3 3 0 0 1-3.53-3.53l.713-3.566a3.01 3.01 0 0 1 .821-1.533L10.905 2H2.167A2.169 2.169 0 0 0 0 4.167v11.666A2.169 2.169 0 0 0 2.167 18h11.666A2.169 2.169 0 0 0 16 15.833V11.1l-3.313 3.308Zm5.53-9.065.546-.546a2.518 2.518 0 0 0 0-3.56 2.576 2.576 0 0 0-3.559 0l-.547.547 3.56 3.56Z"/>
          <path d="M13.243 3.2 7.359 9.081a.5.5 0 0 0-.136.256L6.51 12.9a.5.5 0 0 0 .59.59l3.566-.713a.5.5 0 0 0 .255-.136L16.8 6.757 13.243 3.2Z"/>
        </svg>
      </button>
      <button class="p-1.5 rounded-full hover:bg-gray-700 focus:ring-gray-800"
              hx-post="/rpc/delete_todo"
              hx-vals='{"_id": %1$s}'
              hx-target="#todo-list-area"
              hx-trigger="click">
        <svg class="w-4 h-4 text-red-400" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 18 20">
          <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M1 5h16M7 8v8m4-8v8M7 1h4a1 1 0 0 1 1 1v3H6V2a1 1 0 0 1 1-1ZM3 5h12v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5Z"/>
        </svg>
      </button>
    </div>
  </div>
</li>
$html$,
  $1.id,
  case when $1.done then 'line-through text-gray-400' else '' end,
  api.sanitize_html($1.task),
  (not $1.done)::text
);
$$ language sql stable;

create or replace function api.html_editable_task(_id int) returns "text/html" as $$
select format ($html$
<form id="edit-task-%1$s"
      hx-post="/rpc/change_todo_task"
      hx-headers='{"Accept": "text/html"}'
      hx-vals='{"_id": %1$s}'
      hx-target="#todo-list-area"
      hx-trigger="submit,focusout">
  <input class="bg-gray-50 border text-sm rounded-lg block w-full p-2.5 bg-gray-700 border-gray-600 text-white focus:ring-blue-500 focus:border-blue-500"
         id="task-%1$s" type="text" name="_task" value="%2$s" autofocus>
</form>
$html$,
  id,
  api.sanitize_html(task)
)
from api.todos
where id = _id;
$$ language sql;

