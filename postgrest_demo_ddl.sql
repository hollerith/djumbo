-- DROP FUNCTION api.add_todo(text);

CREATE OR REPLACE FUNCTION api.add_todo(_task text)
 RETURNS "text/html"
 LANGUAGE sql
AS $function$
  insert into api.todos(task) values (_task);
  select api.html_all_todos();
$function$
;

-- DROP FUNCTION api."admin"(text, int4);

CREATE OR REPLACE FUNCTION api.admin(list text, page integer DEFAULT 1)
 RETURNS "text/html"
 LANGUAGE plpgsql
AS $function$
DECLARE
    page_size integer := 10;
    page_offset integer;
    total_rows integer;
    total_pages integer;
    html_output text;
    dynamic_sql text;
    row_html text;
    thead text := '';
    tbody text := '';
    tfoot text := '';
BEGIN

    -- Fetch and construct column headers
    SELECT INTO thead string_agg(format('<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">%s</th>', replace(initcap(column_name), '_', ' ')), '')
    FROM information_schema.columns
    WHERE table_schema = 'api' AND table_name = list;

    -- Calculate the page offset
    page_offset := (page - 1) * page_size;

    -- Generate dynamic SQL using the helper function
    dynamic_sql := api.table_rows_sql('<tr class="hover:text-red-500 odd:bg-yellow-100 even:bg-yellow-300">', '<td class="px-6 py-4 whitespace-nowrap font-medium">', list, page_size, page_offset);

    -- Execute the dynamic SQL and fetch each row
    FOR row_html IN EXECUTE dynamic_sql
    LOOP
        tbody := tbody || row_html;
    END LOOP;

    -- Calculate total rows and pages for pagination
    EXECUTE format('SELECT COUNT(*) FROM api.%I', list) INTO total_rows;
    total_pages := CEIL(total_rows::numeric / page_size);
    tfoot := api.pagination(list, page, total_pages);

    -- Combine all parts into the final HTML output
    html_output := format($html$
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Admin :: %s</title>
            <script src="https://cdn.tailwindcss.com?plugins=forms,typography,aspect-ratio,line-clamp"></script>
            <script src="https://unpkg.com/htmx.org"></script>
        </head>
        <body class="bg-gray-800">
            <div class="flex">
                <!-- Sidebar for desktop -->
                <div class="hidden lg:block bg-black h-screen w-64">
                    <h5 class="mb-3 text-2xl font-bold tracking-tight text-blue-100 p-6">Admin</h5>
                    <ul class="p-6">
                        <li><a href="?list=couriers&page=1" class="text-blue-300 hover:text-blue-500 block">Couriers</a></li>
                        <li><a href="?list=channels&page=1" class="text-blue-300 hover:text-blue-500 block">Channels</a></li>
                        <li><a href="?list=shipments&page=1" class="text-blue-300 hover:text-blue-500 block">Shipments</a></li>
                        <li><a href="?list=orders&page=1" class="text-blue-300 hover:text-blue-500 block">Orders</a></li>
                        <li><a href="?list=merchants&page=1" class="text-blue-300 hover:text-blue-500 block">Merchants</a></li>
                        <li><a href="?list=ticker&page=1" class="text-blue-300 hover:text-blue-500 block">Ticker</a></li>
                        <li><a href="?list=todos&page=1" class="text-blue-300 hover:text-blue-500 block">Todos</a></li>
                    </ul>
                </div>
                <!-- Main content area -->
                <div class="mt-5 p-6 w-full">
                    <h5 class="mb-3 text-2xl font-bold tracking-tight text-blue-100"> :: %s</h5>
                    <div style="overflow-x: auto;">
                        <table class="min-w-full">
                            <thead class="bg-gray-500 text-white">
                              <tr>%s<th>Actions</th></tr>
                            </thead>
                            <tbody class="bg-gray-900">
                              %s
                            </tbody>
                            <tfoot class="bg-gray-500 text-white">
                              <tr>%s</tr>
                            </tfoot>
                        </table>
                    </div>
                </div>
                <!-- Sidebar for desktop -->
                <div class="hidden lg:block bg-black h-screen w-64">
                    <h5 class="mb-3 text-2xl font-bold tracking-tight text-blue-100 p-6">Filters</h5>
                    <ul class="p-6">
                        <li><a href="?list=couriers&page=1" class="text-blue-300 hover:text-blue-500 block">Couriers</a></li>
                        <li><a href="?list=channels&page=1" class="text-blue-300 hover:text-blue-500 block">Channels</a></li>
                        <li><a href="?list=shipments&page=1" class="text-blue-300 hover:text-blue-500 block">Shipments</a></li>
                        <li><a href="?list=orders&page=1" class="text-blue-300 hover:text-blue-500 block">Orders</a></li>
                        <li><a href="?list=merchants&page=1" class="text-blue-300 hover:text-blue-500 block">Merchants</a></li>
                        <li><a href="?list=ticker&page=1" class="text-blue-300 hover:text-blue-500 block">Ticker</a></li>
                        <li><a href="?list=todos&page=1" class="text-blue-300 hover:text-blue-500 block">Todos</a></li>
                    </ul>
                </div>
            </div>
        </body>
        </html>
    $html$, list, list, thead, tbody, tfoot);

    RETURN html_output;
END;
$function$
;

-- DROP FUNCTION api.admin_todos();

CREATE OR REPLACE FUNCTION api.admin_todos()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare
  html_output text;
begin
  html_output := '
    <table class="min-w-full">
      <thead class="bg-gray-500 text-white">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">ID</th>
          <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">Task</th>
          <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">Done</th>
        </tr>
      </thead>
      <tbody class="bg-gray-900">';

  select into html_output html_output || string_agg(format('
        <tr class="hover:text-red-500 odd:bg-yellow-100 even:bg-yellow-300">
          <td class="px-6 py-4 whitespace-nowrap font-medium text-gray-900">%s</td>
          <td class="px-6 py-4 whitespace-nowrap font-medium text-gray-900">%s</td>
          <td class="px-6 py-4 whitespace-nowrap font-medium text-gray-900">%s</td>
        </tr>', id, task, case when done then 'Yes' else 'No' end), '')
  from api.todos;

  html_output := html_output || '
      </tbody>
    </table>';

  return html_output;
end
$function$
;

-- DROP FUNCTION api.change_todo_state(int4, bool);

CREATE OR REPLACE FUNCTION api.change_todo_state(_id integer, _done boolean)
 RETURNS "text/html"
 LANGUAGE sql
AS $function$
  update api.todos set done = _done where id = _id;
  select api.html_all_todos();
$function$
;

-- DROP FUNCTION api.change_todo_task(int4, text);

CREATE OR REPLACE FUNCTION api.change_todo_task(_id integer, _task text)
 RETURNS "text/html"
 LANGUAGE sql
AS $function$
  update api.todos set task = _task where id = _id;
  select api.html_all_todos();
$function$
;

-- DROP FUNCTION api.delete_todo(int4);

CREATE OR REPLACE FUNCTION api.delete_todo(_id integer)
 RETURNS "text/html"
 LANGUAGE sql
AS $function$
  delete from api.todos where id = _id;
  select api.html_all_todos();
$function$
;

-- DROP FUNCTION api.html_all_todos();

CREATE OR REPLACE FUNCTION api.html_all_todos()
 RETURNS text
 LANGUAGE sql
AS $function$
  select coalesce(
    '<ul id="todo-list" role="list" class="divide-y divide-gray-700 text-gray-100">'
      || string_agg(api.html_todo(t), '' order by t.id) ||
    '</ul>',
    '<p class="text-gray-100">There is nothing else to do.</p>'
  )
  from api.todos t;
$function$
;

-- DROP FUNCTION api.html_editable_task(int4);

CREATE OR REPLACE FUNCTION api.html_editable_task(_id integer)
 RETURNS "text/html"
 LANGUAGE sql
AS $function$
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
$function$
;

-- DROP FUNCTION api.html_todo(api.todos);

CREATE OR REPLACE FUNCTION api.html_todo(api.todos)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
;

-- DROP FUNCTION api."index"();

CREATE OR REPLACE FUNCTION api.index()
 RETURNS "text/html"
 LANGUAGE sql
AS $function$
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
$function$
;

-- DROP FUNCTION api.pagination(text, int4, int4);

CREATE OR REPLACE FUNCTION api.pagination(list text, current_page integer, total_pages integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    pagination_links text := '';
    i integer;
BEGIN
    IF total_pages <= 5 THEN
        pagination_links := 'Pages ';
        FOR i IN 1..total_pages LOOP
            pagination_links := pagination_links || format('<a href="?list=%s&page=%s">%s</a>', list, i, i);
            IF i < total_pages THEN
                pagination_links := pagination_links || ', ';
            END IF;
        END LOOP;
    ELSE
        -- Always link to the first page
        pagination_links := format('<a href="?list=%s&page=1">Page 1</a> ', list);
        IF current_page > 2 THEN
            pagination_links := pagination_links || '... ';
        END IF;

        -- Show one page before and after the current page, if possible
        FOR i IN GREATEST(2, current_page - 1)..LEAST(total_pages - 1, current_page + 1) LOOP
            pagination_links := pagination_links || format('<a href="?list=%s&page=%s">%s</a> ', list, i, i);
        END LOOP;

        IF current_page < total_pages - 1 THEN
            pagination_links := pagination_links || '... ';
        END IF;

        -- Always link to the last page
        pagination_links := pagination_links || format('<a href="?list=%s&page=%s">of %s</a>', list, total_pages, total_pages);
    END IF;

    RETURN format($html$
      <td colspan="100%%" class="px-6 py-4 whitespace-nowrap font-medium">%s</td>
    $html$, pagination_links);
END;
$function$
;

-- DROP FUNCTION api.sanitize_html(text);

CREATE OR REPLACE FUNCTION api.sanitize_html(text)
 RETURNS text
 LANGUAGE sql
AS $function$
  select replace(replace(replace(replace(replace($1, '&', '&amp;'), '"', '&quot;'),'>', '&gt;'),'<', '&lt;'), '''', '&apos;')
$function$
;

-- DROP FUNCTION api.table_rows_sql(text, text, text, int4, int4);

CREATE OR REPLACE FUNCTION api.table_rows_sql(row_tag text, col_tag text, tablename text, page_size integer, page_offset integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    column_sql TEXT := '';
    dynamic_sql TEXT;
    primary_key_column text;
BEGIN
    -- Fetch the primary key column name
    SELECT kcu.column_name INTO primary_key_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    WHERE tc.table_schema = 'api' AND tc.table_name = tablename AND tc.constraint_type = 'PRIMARY KEY';

    -- Construct the SQL part for column data wrapped in col_tag, handling NULL values
    SELECT INTO column_sql
        string_agg(format('''%s'' || COALESCE(%I::text, '''') || ''%s''', col_tag, column_name, '</td>'), ' || ')
    FROM information_schema.columns
    WHERE table_schema = 'api' AND table_name = tablename;

    dynamic_sql := format('SELECT ''%s'' || %s || ''<td class="flex justify-center align-middle py-4">
    <button class="p-1.5 rounded-full hover:bg-gray-700 focus:ring-gray-800" hx-get="/rpc/edit?form=%s&_id='' || %I || ''" hx-target="#list" hx-trigger="click">
    <svg class="w-4 h-4 text-blue-300" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 20 18">
        <path d="M12.687 14.408a3.01 3.01 0 0 1-1.533.821l-3.566.713a3 3 0 0 1-3.53-3.53l.713-3.566a3.01 3.01 0 0 1 .821-1.533L10.905 2H2.167A2.169 2.169 0 0 0 0 4.167v11.666A2.169 2.169 0 0 0 2.167 18h11.666A2.169 2.169 0 0 0 16 15.833V11.1l-3.313 3.308Zm5.53-9.065.546-.546a2.518 2.518 0 0 0 0-3.56 2.576 2.576 0 0 0-3.559 0l-.547.547 3.56 3.56Z"/>
        <path d="M13.243 3.2 7.359 9.081a.5.5 0 0 0-.136.256L6.51 12.9a.5.5 0 0 0 .59.59l3.566-.713a.5.5 0 0 0 .255-.136L16.8 6.757 13.243 3.2Z"/>
    </svg>
    </button>
    <button class="p-1.5 rounded-full hover:bg-gray-700 focus:ring-gray-800" hx-get="/rpc/delete?form=%s&_id='' || %I || ''" hx-target="#list" hx-trigger="click">
    <svg class="w-4 h-4 text-red-400" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 18 20">
        <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M1 5h16M7 8v8m4-8v8M7 1h4a1 1 0 0 1 1 1v3H6V2a1 1 0 0 1 1-1ZM3 5h12v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5Z"/>
    </svg>
    </button>
</td>'' || ''</tr>'' FROM api.%I LIMIT %L OFFSET %L', row_tag, column_sql, tablename, primary_key_column, tablename, primary_key_column, tablename, page_size, page_offset);

    RETURN dynamic_sql;
END;
$function$
;

-- DROP FUNCTION api.table_rows_sql(text, text, text, int4);

CREATE OR REPLACE FUNCTION api.table_rows_sql(row_tag text, col_tag text, tablename text, page_size integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    column_sql TEXT := '';
    dynamic_sql TEXT;
BEGIN
    -- Construct the SQL part for column data wrapped in col_tag, handling NULL values
    SELECT INTO column_sql
        string_agg(format('''%s'' || COALESCE(%I::text, '''') || ''%s''', col_tag, column_name, '</td>'), ' || ')
    FROM information_schema.columns
    WHERE table_schema = 'api' AND table_name = tablename;

    -- Construct the full dynamic SQL statement for fetching rows with HTML markup
    dynamic_sql := format('SELECT ''%s'' || %s || ''</tr>'' FROM api.%I LIMIT %L', row_tag, column_sql, tablename, page_size);

    RETURN dynamic_sql;
END;
$function$
;

-- DROP FUNCTION api.to_base32(varbit);

CREATE OR REPLACE FUNCTION api.to_base32(bs bit varying)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    result  text;
    _cur    bigint;
    _w      bit(64);
    _holder bit(64) = 31 :: bit(64);
    _chars  char(32) = 'abcdefghjklmnpqrstuvwxyz23456789';
BEGIN
    result = '';
    _w = bs :: bit(64) >> (64 - length(bs));
    loop
        exit when _w :: bigint = 0;
        _cur = (_w & _holder) :: bigint + 1;
        result = substr(_chars, _cur :: integer, 1) || result;
        _w = _w >> 5;
    end loop;
    RETURN result;
END;
$function$
;