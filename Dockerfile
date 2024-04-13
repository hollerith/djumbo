FROM postgres:16

# Update packages and install the required tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-plpython3-16 \
      python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --break-system-packages requests Jinja2

# Expose the PostgreSQL port
EXPOSE 5432

# Start the PostgreSQL server with modified log level
CMD ["postgres", "-c", "log_min_messages=info"]
