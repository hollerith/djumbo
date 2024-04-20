-- drop function api."admin"(text, int4);
create or replace function api.admin(list text, page integer default 1) returns "text/html" as $$
declare
    html_output text;
    context json;
    session_info json;
begin

    -- Fetch the user session information using the auth.authenticate() function
    select auth.authenticate() into session_info;

    html_output = api.sheet(list, page);

    context := json_build_object(
        'current_user', current_user,
        'current_database', current_database(),
        'current_schema', current_schema(),
        'table_html', html_output,
        'login', session_info
    );

    return api.render('admin.html', context);
end;
$$ language plpgsql;


-- drop function api."sheet"(text, int4);
create or replace function api.sheet(list text, page_no integer default 1) returns "text/html" as $$
declare
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
    context json;
    login json;
begin

    -- Fetch and construct column headers
    select into thead string_agg(format('<th class="border border-gray-200 px-4 py-2 text-left">%s</th>', replace(initcap(column_name), '_', ' ')), '')
      from information_schema.columns
     where table_schema = 'api'
       and table_name = list;

    -- Calculate the page offset
    page_offset := (page_no - 1) * page_size;

    -- Generate dynamic SQL using the helper function
    dynamic_sql := api.table_rows_sql('<tr>', '<td class="border border-gray-200 px-4 py-2 text-left">', list, page_size, page_offset);

    -- Execute the dynamic SQL and fetch each row
    for row_html in execute dynamic_sql
    loop
        tbody := tbody || row_html;
    end loop;

    -- Calculate total rows and pages for pagination
    execute format('SELECT COUNT(*) FROM api.%I', list) into total_rows;

    total_pages := CEIL(total_rows::numeric / page_size);
    tfoot := api.pagination(list, page_no, total_pages);

    context := json_build_object(
        'id', list,
        'title', initcap(list),
        'thead', thead,
        'tbody', tbody,
        'tfoot', tfoot
    );

    return api.render('table.html', context);
end;
$$ language plpgsql;

-- drop function api.table_rows_sql(text, text, text, int4, int4);
create or replace function api.table_rows_sql(row_tag text, col_tag text, tablename text, page_size integer, page_offset integer) returns text as $$
declare
    column_sql text := '';
    dynamic_sql text;
    primary_key_column text;
begin
    -- Fetch the primary key column name
    select kcu.column_name into primary_key_column
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu on tc.constraint_name = kcu.constraint_name
     where tc.table_schema = 'api' and tc.table_name = tablename and tc.constraint_type = 'PRIMARY KEY';

    -- Construct the SQL part for column data wrapped in col_tag, handling NULL values
    select into column_sql
           string_agg(format('''%s'' || coalesce(%I::text, '''') || ''%s''', col_tag, column_name, '</td>'), ' || ')
      from information_schema.columns
     where table_schema = 'api' and table_name = tablename;

    if primary_key_column is null then
        dynamic_sql := format('SELECT ''<tr id="pk-'' || row_number() over () || ''">'' || %s || ''</tr>'' FROM api.%I LIMIT %L OFFSET %L', column_sql, tablename, page_size, page_offset);
    else
        dynamic_sql := format('SELECT ''<tr id="'' || %I || ''">'' || %s || ''</tr>'' FROM api.%I LIMIT %L OFFSET %L', primary_key_column, column_sql, tablename, page_size, page_offset);
    end if;

    return dynamic_sql;
end;
$$ language plpgsql;

-- drop function api.pagination(text, int4, int4);
create or replace function api.pagination(list text, current_page integer, total_pages integer)
 returns text as $$
declare
    pagination_links text := '';
    i integer;
begin
    if total_pages <= 5 then
        pagination_links := 'Page ';
        for i in 1..total_pages loop
            pagination_links := pagination_links || format('<a class="hover:text-blue-500" href="" hx-get="/sheet?list=%s&page_no=%s" hx-target="#%s" hx-swap="outerHTML" hx-headers=''{"Accept": "text/html"}''>%s</a>', list, i, list, i);
            if i < total_pages then
                pagination_links := pagination_links || ', ';
            end if;
        end loop;
    else
        -- Always link to the first page
        pagination_links := format('Page <a class="hover:text-blue-500" href="" hx-get="/sheet?list=%s&page=1" hx-target="#%s" hx-swap="outerHTML" hx-headers=''{"Accept": "text/html"}''>1</a> ', list, list);
        if current_page > 2 then
            pagination_links := pagination_links || '... ';
        end if;

        -- Show one page before and after the current page, if possible
        for i in greatest(2, current_page - 1)..least(total_pages - 1, current_page + 1) loop
            pagination_links := pagination_links || format('<a class="hover:text-blue-500" href="" hx-get="/sheet?list=%s&page_no=%s" hx-target="#%s" hx-swap="outerHTML" hx-headers=''{"Accept": "text/html"}''>%s</a> ', list, i, list, i);
        end loop;

        if current_page < total_pages - 1 then
            pagination_links := pagination_links || '... ';
        end if;

        -- Always link to the last page
        pagination_links := pagination_links || format('of <a class="hover:text-blue-500" href="" hx-get="/sheet?list=%s&page_no=%s" hx-target="#%s" hx-swap="outerHTML" hx-headers=''{"Accept": "text/html"}''>%s</a>', list, total_pages, list, total_pages);
    end if;

    return format($html$
      <td colspan="100%%" class="px-4 py-2 whitespace-nowrap font-medium">%s</td>
    $html$, pagination_links);
end;
$$ language plpgsql;

grant execute on function api.admin(text, integer) to web_anon, web_user;
grant execute on function api.sheet(text, integer) to web_anon, web_user;
grant execute on function api.table_rows_sql(text, text, text, integer, integer) to web_anon, web_user;
grant execute on function api.pagination(text, integer, integer) to web_anon, web_user;
