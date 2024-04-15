-- drop function api."admin"(text, int4);
create or replace function api.admin(list text, page integer default 1) returns "text/html" as $$
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
    user_session_info json;
begin

    -- Fetch and construct column headers
    select into thead string_agg(format('<th class="border border-gray-200 px-4 py-2 text-left">%s</th>', replace(initcap(column_name), '_', ' ')), '')
      from information_schema.columns
     where table_schema = 'api'
       and table_name = list;

    -- Calculate the page offset
    page_offset := (page - 1) * page_size;

    -- Generate dynamic SQL using the helper function
    dynamic_sql := api.table_rows_sql('<tr class="odd:bg-blue-100 even:bg-yellow-50">', '<td class="border border-gray-200 px-4 py-2 text-left">', list, page_size, page_offset);

    -- Execute the dynamic SQL and fetch each row
    for row_html in execute dynamic_sql
    loop
        tbody := tbody || row_html;
    end loop;

    -- Calculate total rows and pages for pagination
    execute format('SELECT COUNT(*) FROM api.%I', list) into total_rows;

    total_pages := CEIL(total_rows::numeric / page_size);
    tfoot := api.pagination(list, page, total_pages);

    -- Combine all parts into the final HTML output
    html_output := format($html$
        <!-- Main content area -->
            <div class="mb-8">
                <h2 class="text-xl font-semibold mb-4">%s</h2>
                <table class="min-w-full table-auto border-collapse border border-gray-200">
                    <thead class="bg-gray-200">
                        <tr>%s<th>Actions</th></tr>
                    </thead>
                    <tbody>
                        %s
                    </tbody>
                    <tfoot class="bg-gray-500 text-white">
                        <tr>%s</tr>
                    </tfoot>
                </table>
            </div>
        </div>
    $html$, initcap(list), thead, tbody, tfoot);

    -- Fetch the user session information using the auth.authenticate() function
    select auth.authenticate() into user_session_info;

    context := json_build_object(
        'safe_html', html_output,
        'user_session_info', user_session_info
    );

    return api.render('admin.html', context);
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
        pagination_links := 'Pages ';
        for i in 1..total_pages loop
            pagination_links := pagination_links || format('<a href="/admin?list=%s&page=%s">%s</a>', list, i, i);
            if i < total_pages then
                pagination_links := pagination_links || ', ';
            end if;
        end loop;
    else
        -- Always link to the first page
        pagination_links := format('<a href="?list=%s&page=1">Page 1</a> ', list);
        if current_page > 2 then
            pagination_links := pagination_links || '... ';
        end if;

        -- Show one page before and after the current page, if possible
        for i in greatest(2, current_page - 1)..least(total_pages - 1, current_page + 1) loop
            pagination_links := pagination_links || format('<a href="/admin?list=%s&page=%s">%s</a> ', list, i, i);
        end loop;

        if current_page < total_pages - 1 then
            pagination_links := pagination_links || '... ';
        end if;

        -- Always link to the last page
        pagination_links := pagination_links || format('<a href="/admin?list=%s&page=%s">of %s</a>', list, total_pages, total_pages);
    end if;

    return format($html$
      <td colspan="100%%" class="px-6 py-4 whitespace-nowrap font-medium">%s</td>
    $html$, pagination_links);
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

    dynamic_sql := format('SELECT ''%s'' || %s || ''<td class="flex justify-center align-middle py-4">
    <button class="p-1.5 rounded-full hover:bg-gray-700 focus:ring-gray-800" hx-get="/edit?form=%s&_id='' || %I || ''" hx-target="#list" hx-trigger="click">
    <svg class="w-4 h-4 text-blue-300" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 20 18">
        <path d="M12.687 14.408a3.01 3.01 0 0 1-1.533.821l-3.566.713a3 3 0 0 1-3.53-3.53l.713-3.566a3.01 3.01 0 0 1 .821-1.533L10.905 2H2.167A2.169 2.169 0 0 0 0 4.167v11.666A2.169 2.169 0 0 0 2.167 18h11.666A2.169 2.169 0 0 0 16 15.833V11.1l-3.313 3.308Zm5.53-9.065.546-.546a2.518 2.518 0 0 0 0-3.56 2.576 2.576 0 0 0-3.559 0l-.547.547 3.56 3.56Z"/>
        <path d="M13.243 3.2 7.359 9.081a.5.5 0 0 0-.136.256L6.51 12.9a.5.5 0 0 0 .59.59l3.566-.713a.5.5 0 0 0 .255-.136L16.8 6.757 13.243 3.2Z"/>
    </svg>
    </button>
    <button class="p-1.5 rounded-full hover:bg-gray-700 focus:ring-gray-800" hx-get="/delete?form=%s&_id='' || %I || ''" hx-target="#list" hx-trigger="click">
    <svg class="w-4 h-4 text-red-400" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 18 20">
        <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M1 5h16M7 8v8m4-8v8M7 1h4a1 1 0 0 1 1 1v3H6V2a1 1 0 0 1 1-1ZM3 5h12v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5Z"/>
    </svg>
    </button>
</td>'' || ''</tr>'' FROM api.%I LIMIT %L OFFSET %L', row_tag, column_sql, tablename, primary_key_column, tablename, primary_key_column, tablename, page_size, page_offset);

    return dynamic_sql;
end;
$$ language plpgsql;

-- drop function api.to_base32(varbit);
create or replace function api.to_base32(bs bit varying) returns text as $$
declare
    result text;
    _cur    bigint;
    _w      bit(64);
    _holder bit(64) = 31 :: bit(64);
    _chars char(32) = 'abcdefghjklmnpqrstuvwxyz23456789';
begin
    result = '';
    _w = bs :: bit(64) >> (64 - length(bs));
    loop
        exit when _w :: bigint = 0;
        _cur = (_w & _holder) :: bigint + 1;
        result = substr(_chars, _cur :: integer, 1) || result;
        _w = _w >> 5;
    end loop;
    return result;
end;
$$ language plpgsql;

grant execute on function api.admin(text, integer) to web_anon, web_user;
grant execute on function api.to_base32(varbit) to web_anon, web_user;
grant execute on function api.table_rows_sql(text, text, text, integer, integer) to web_anon, web_user;
grant execute on function api.pagination(text, integer, integer) to web_anon, web_user;
