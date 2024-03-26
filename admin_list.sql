create or replace function format_heading(column_name text)
returns text language sql as $$
    select string_agg(initcap(word), ' ')
    from regexp_split_to_table(column_name, '_') as word;
$$;

create or replace function api.admin(list text, page integer default 1)
returns "text/html" language plpgsql as $$
declare
  list_item text;
  page_size integer := 10;
  offset_amount integer := (page - 1) * page_size;
  result_set record;
  total_rows integer;
  total_pages integer;
  html_output text := '';
  heading text;
begin
  -- Attempt to find a text or varchar attribute
  select column_name into list_item
    from information_schema.columns
   where table_schema = 'api'
     and table_name = list
     and udt_name in ('text', 'varchar')
   order by case when udt_name = 'text' then 1 else 2 end, ordinal_position
   limit 1;

  if list_item is null then
    return 'No suitable attributes found in the specified table.';
  end if;

  -- Prepare heading from attribute name
  select string_agg(initcap(word), ' ') into heading
    from regexp_split_to_table(list_item, '_') as word;

  -- Calculate total rows and pages for pagination
  execute format('select count(*) from api.%I', list) into total_rows;
  total_pages := ceil(total_rows::numeric / page_size);

  -- Start table and add heading
  html_output := format('<table class="min-w-full"><thead class="bg-gray-500 text-white"><tr><th scope="col" class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">%s</th></tr></thead><tbody class="bg-gray-900">', heading);

  -- Prepare the dynamic SQL query string and execute
  for result_set in execute format($f$
    select id, %I as list_item
      from api.%I
     order by id
     limit %L offset %L
  $f$, list_item, list, page_size, offset_amount) loop
    -- Add table rows with hover and text color, alternating background for odd and even rows
    html_output := html_output || format('<tr class="hover:text-red-500 odd:bg-yellow-100 even:bg-yellow-300"><td class="px-6 py-4 whitespace-nowrap font-medium">%s</td></tr>', result_set.list_item);
  end loop;

  -- Close table tags and add the footer with pagination details
  html_output := html_output || format('</tbody><tfoot class="bg-gray-500 text-white"><tr><td colspan="100%%" class="px-6 py-4 whitespace-nowrap font-medium">Page %s of %s</td></tr></tfoot></table>', page, total_pages);

  return format($html$
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Admin - %s</title>
  <script src="https://cdn.tailwindcss.com?plugins=forms,typography,aspect-ratio,line-clamp"></script>
</head>
<body class="bg-gray-900">
  <div class="flex justify-center">
    <div class="max-w-lg mt-5 p-6 bg-gray-800 border border-gray-800 rounded-lg shadow-xl">
      <h5 class="mb-3 text-2xl font-bold tracking-tight text-white">Admin - Listing: %s</h5>
      %s
    </div>
  </div>
</body>
</html>
$html$, list, list, html_output);
end;
$$;


select admin('todos', 1);


create or replace function api.admin(list text, page integer default 1)
returns "text/html" language plpgsql as $$
declare
  page_size integer := 10;
  offset_amount integer := (page - 1) * page_size;
  total_rows integer;
  total_pages integer;
  html_output text := '';
  column_info record;
  row record;
  row_data text;
begin
  -- Calculate total rows and pages for pagination
  execute format('SELECT COUNT(*) FROM api.%I', list) into total_rows;
  total_pages := ceil(total_rows::numeric / page_size);

  -- Start table
  html_output := '<table class="min-w-full"><thead class="bg-gray-500 text-white"><tr>';

  -- Fetch and construct column headers
  for column_info in
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'api' AND table_name = list
      ORDER BY ordinal_position
  loop
    html_output := html_output || format('<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">%s</th>', replace(initcap(column_info.column_name), '_', ' '));
  end loop;

  html_output := html_output || '</tr></thead><tbody class="bg-gray-900">';

  -- Construct the dynamic SQL query string and execute
  execute format('SELECT * FROM api.%I ORDER BY id LIMIT %L OFFSET %L', list, page_size, offset_amount) into row;

  for row in execute format('SELECT * FROM api.%I ORDER BY id LIMIT %L OFFSET %L', list, page_size, offset_amount)
  loop
    html_output := html_output || '<tr class="hover:text-red-500 odd:bg-yellow-100 even:bg-yellow-300">';
    for column_info in
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'api' AND table_name = list
        ORDER BY ordinal_position
    loop
      execute format('SELECT %I::text FROM api.%I WHERE id = $1', column_info.column_name, list) using row.id into row_data;
      html_output := html_output || format('<td class="px-6 py-4 whitespace-nowrap font-medium">%s</td>', row_data);
    end loop;
    html_output := html_output || '</tr>';
  end loop;

  html_output := html_output || format('</tbody><tfoot class="bg-gray-500 text-white"><tr><td colspan="100%%" class="px-6 py-4 whitespace-nowrap font-medium">Page %s of %s</td></tr></tfoot></table>', page, total_pages);

  return format('<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Admin - %s</title><script src="https://cdn.tailwindcss.com?plugins=forms,typography,aspect-ratio,line-clamp"></script></head><body class="bg-gray-900"><div class="flex justify-center"><div class="max-w-lg mt-5 p-6 bg-gray-800 border border-gray-800 rounded-lg shadow-xl"><h5 class="mb-3 text-2xl font-bold tracking-tight text-blue-100">Admin - Listing: %s</h5>%s</div></div></body></html>', list, list, html_output);
end;
$$;


create or replace function generate_table_row_select(schema_name text, table_name text)
returns text language sql as $$
declare
  column_expressions text := '';
begin
  select string_agg('format(''<td class="px-6 py-4 whitespace-nowrap font-medium text-gray-900">'' || ' || column_name || ' || ''</td>'', ' || column_name || ')', ' || ')
  into column_expressions
  from information_schema.columns
  where table_schema = schema_name and table_name = table_name
  order by ordinal_position;

  return 'SELECT string_agg('<tr>' || ' || column_expressions || ' || '</tr>', '') FROM ' || quote_ident(schema_name) || '.' || quote_ident(table_name);
end
$$;


create or replace function api.admin_todos()
returns text language plpgsql as $$
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
$$;

select api.admin_todos()

create or replace function generate_admin_function(schema_name text, table_name text)
returns void language plpgsql as $$
declare
  column_list text := '';
  function_sql text;
begin
  -- Fetch columns for the table and format them for HTML
  select string_agg(format(''<td>'' || %I || ''</td>'', column_name), '')
  into column_list
  from information_schema.columns
  where table_schema = schema_name and table_name = table_name
  order by ordinal_position;

  -- Construct the function SQL
  function_sql := format($f$
    create or replace function %I.admin_%I()
    returns text language sql as $$
    select '<table><thead><tr>' ||
    (select string_agg('<th>' || column_name || '</th>', '') from information_schema.columns where table_schema = %L and table_name = %L) ||
    '</tr></thead><tbody>' ||
    (select string_agg(format('<tr>%s</tr>', %s), '') from %I.%I) ||
    '</tbody></table>'
    $$;
  $f$, schema_name, table_name, schema_name, table_name, column_list, schema_name, table_name);

  -- Execute the constructed function SQL
  execute function_sql;
end
$$;

create or replace function generate_admin_function(schema_name text, table_name text)
returns void as $$
declare
  column_expressions text := '';
  dynamic_sql text;
begin
  -- Aggregate column names into a single string for the SELECT statement
  select into column_expressions
    string_agg(format(''<td>'' || %I || ''</td>'', column_name), ' || ', '')
  from information_schema.columns
  where table_schema = schema_name and table_name = table_name
  order by ordinal_position;

  -- Construct the dynamic function creation SQL
  dynamic_sql := format($fmt$
create or replace function %I.admin_%I()
returns text as $$
declare
  result text;
begin
  select into result string_agg(format('<tr>%s</tr>', %s), '')
  from %I.%I;
  return '<table><thead><tr>' ||
         (select string_agg(format('<th>%s</th>', column_name), '')
          from information_schema.columns
          where table_schema = %L and table_name = %L) ||
         '</tr></thead><tbody>' || result || '</tbody></table>';
end
$$ language plpgsql;
$fmt$, schema_name, table_name, column_expressions, schema_name, table_name);

  -- Execute the dynamic SQL to create the function
  execute dynamic_sql;
end
$$ language plpgsql;

select generate_admin_function('api', 'todos');

-- latest good
CREATE OR REPLACE FUNCTION api.admin(list text, page integer DEFAULT 1)
 RETURNS "text/html"
 LANGUAGE plpgsql
AS $function$
DECLARE
    page_size integer := 10;
    total_rows integer;
    total_pages integer;
    html_output text;
    dynamic_sql text;
    row_html text;
BEGIN
    -- Calculate total rows and pages for pagination
    EXECUTE format('SELECT COUNT(*) FROM api.%I', list) INTO total_rows;
    total_pages := CEIL(total_rows::numeric / page_size);

    -- Append column headers to html_output
    html_output := '<div style="overflow-x: auto;"><table class="min-w-full"><thead class="bg-gray-500 text-white"><tr>';

    -- Fetch and construct column headers
    SELECT INTO column_headers string_agg(format('<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider">%s</th>', replace(initcap(column_name), '_', ' ')), '')
    FROM information_schema.columns
    WHERE table_schema = 'api' AND table_name = list;

    -- Close the table header
    html_output := html_output || '</tr></thead><tbody class="bg-gray-900">';

    -- Generate dynamic SQL using the helper function
    dynamic_sql := api.table_rows_sql('<tr class="hover:text-red-500 odd:bg-yellow-100 even:bg-yellow-300">', '<td class="px-6 py-4 whitespace-nowrap font-medium">', list, page_size);

    -- Execute the dynamic SQL and fetch each row
    FOR row_html IN EXECUTE dynamic_sql
    LOOP
        html_output := html_output || row_html;
    END LOOP;

    -- Close the table and append pagination
    html_output := html_output || format('</tbody><tfoot class="bg-gray-500 text-white"><tr><td colspan="100%%" class="px-6 py-4 whitespace-nowrap font-medium">Page %s of %s</td></tr></tfoot></table>', page, total_pages);

    -- Return the complete HTML document
    RETURN FORMAT('<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Admin - %s</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900">
    <div class="flex justify-center">
        <div class="mt-5 p-6 bg-gray-800 border border-gray-800 rounded-lg shadow-xl">
            <h5 class="mb-3 text-2xl font-bold tracking-tight text-blue-100">Admin - Listing: %s</h5>
            %s
        </div>
    </div>
</body>
</html>', list, list, html_output);
END;
$function$


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

    dynamic_sql := format('SELECT ''%s'' || %s || ''<td class="flex justify-center items-center h-full">
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
