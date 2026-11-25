FROM postgres:16

# pgloader 3.6.x desde los repositorios Debian de la imagen base.
# psql (cliente PostgreSQL) ya viene incluido en postgres:16.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      pgloader \
      gettext-base \
      tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
