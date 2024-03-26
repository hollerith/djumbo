CREATE OR REPLACE FUNCTION api.admin(list text, page integer DEFAULT 1) RETURNS "text/html" LANGUAGE plpgsql AS $function$
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
                    </ul>
                </div>
                <!-- Main content area -->
                <div class="mt-5 p-6 w-full">
                    <h5 class="mb-3 text-2xl font-bold tracking-tight text-blue-100"> :: %s</h5>
                    <div style="overflow-x: auto;">
                        <table class="min-w-full">
                            <thead class="bg-gray-500 text-white">
                              <tr>%s</tr>
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
            </div>
        </body>
        </html>
    $html$, list, list, thead, tbody, tfoot);

    RETURN html_output;
END;
$function$
