# Djumbo

<div align="center">
    <img src="static/djumbo_512.png" alt="Djumbo Logo" width="512">
</div>

## Description

Djumbo is a powerful and flexible web application framework built on top of PostgreSQL, designed to streamline the development of dynamic web applications. It leverages the power of PostgreSQL's advanced features, such as JSONB support, PL/pgSQL functions, and triggers, to provide a seamless backend experience. Djumbo aims to simplify the development process by offering a structured approach to building web applications, with a focus on security, performance, and ease of use.

Inspired by Dan McKinley [^1] and Stephan Schmidt [^2].


## Features

- **PostgreSQL-centric**: Utilizes PostgreSQL's advanced features to provide a robust backend.
- **Dynamic Routing**: Automatically generates routes based on your database schema and functions.
- **Security**: Built-in authentication and authorization mechanisms, including role-based access control.
- **Performance**: Optimized for speed, with efficient data handling and minimal overhead.
- **Ease of Use**: Simple setup and configuration, with a focus on developer productivity.

## Installation

1. **Clone the Repository**: First, clone the Djumbo repository to your local machine.

    ```bash
    git clone https://github.com/hollerith/djumbo.git
    ```

2. **Build and Run with Docker Compose**: Djumbo provides a `docker-compose.yml` file for easy setup and deployment. Build and run the Docker containers using the following command.

    ```bash
    docker-compose up --build
    ```

3. **Explore Sample Web Pages**: Djumbo includes sample web pages defined in `pages.sql`, along with a utility function to render templates with Jinja2. Explore these examples to get started with your own web pages. Samples use HTMX and tailwindcss but you could easily use something else.

4. **Shopify App Example**: For those interested in integrating with Shopify, a sample app implementation is provided in `shopify.sql`. This example demonstrates how to interact with the Shopify API from within your Djumbo application. (wip Incomplete)

## Usage

Djumbo provides a simple and intuitive interface for developing web applications. Here's a basic example of how to define a route and a corresponding function in your `pages.sql` file:

```sql
-- Define a simple route
create or replace function api.hello_world()
returns "text/html" language plpgsql as $$
begin
    context := json_build_object(
        'title', 'Hello World'
    );
    return api.render('template.html', context::json);
end;
$$;
```

This SQL function can be accessed by navigating to `/rpc/hello_world` in your web browser. Note that we use nginx rewrite rules to remove the postgrest default "/rpc/" part.

## License

Djumbo is open-source software licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Notes

- [^1]: https://boringtechnology.club
- [^2]: https://www.radicalsimpli.city
