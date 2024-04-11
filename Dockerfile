FROM postgres:16

RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-plpython3-16 \
      python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages requests Jinja2 bottle

EXPOSE 5432
CMD ["postgres"]
