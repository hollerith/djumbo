create or replace function api.index() returns "text/html" as $$
  select $html$
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>PostgREST + HTMX To-Do List</title>
      <!-- Tailwind for CSS styling -->
      <link href="https://unpkg.com/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    </head>
    <body class="bg-gray-900">
      <div class="flex justify-center">
        <div class="max-w-lg mt-5 p-6 bg-gray-800 border border-gray-800 rounded-lg shadow-xl">
          <h5 class="mb-3 text-2xl font-bold tracking-tight text-white">PostgREST + HTMX To-Do List</h5>
        </div>
      </div>
    </body>
    </html>
  $html$;
$$ language sql;

