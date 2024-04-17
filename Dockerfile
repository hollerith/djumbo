FROM postgres:16

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      build-essential \
      postgresql-server-dev-16 \
      postgresql-plpython3-16 \
      python3-pip \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --break-system-packages requests Jinja2

# Clone and build pg_cron
RUN git clone https://github.com/citusdata/pg_cron.git \
    && cd pg_cron \
    && make && make install

# Setup pg_cron: Modify the PostgreSQL main configuration file
RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "cron.database_name = 'postgres'" >> /usr/share/postgresql/postgresql.conf.sample

# Expose the PostgreSQL port
EXPOSE 5432

# Start the PostgreSQL server with modified log level
CMD ["postgres", "-c", "log_min_messages=info"]
