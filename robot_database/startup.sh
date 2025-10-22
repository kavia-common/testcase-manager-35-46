#!/bin/bash

# Minimal PostgreSQL startup script with full paths + migrations
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Helper to run psql as postgres
psql_as_postgres () {
  sudo -u postgres ${PG_BIN}/psql -v ON_ERROR_STOP=1 "$@"
}

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
else
    # Also check if there's a PostgreSQL process running (in case pg_isready fails)
    if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
        echo "Found existing PostgreSQL process on port ${DB_PORT}"
        echo "Attempting to verify connection..."
        if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
            echo "Database ${DB_NAME} is accessible."
        fi
    else
        # Initialize PostgreSQL data directory if it doesn't exist
        if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
            echo "Initializing PostgreSQL..."
            sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
        fi

        # Start PostgreSQL server in background
        echo "Starting PostgreSQL server..."
        sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &
        export PG_BG_PID=$$

        # Wait for PostgreSQL to start
        echo "Waiting for PostgreSQL to start..."
        for i in {1..15}; do
            if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
                echo "PostgreSQL is ready!"
                break
            fi
            echo "Waiting... ($i/15)"
            sleep 2
        done
    fi
fi

# Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
psql_as_postgres -p ${DB_PORT} -d postgres << EOF
-- Create user if doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# Ensure schema permissions inside the DB
psql_as_postgres -p ${DB_PORT} -d ${DB_NAME} << EOF
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Apply migrations idempotently
MIGRATIONS_DIR="$(dirname "$0")/migrations"
if [ -d "${MIGRATIONS_DIR}" ]; then
  echo "Applying migrations from ${MIGRATIONS_DIR}..."
  # Ensure schema_migrations table exists in target DB
  psql_as_postgres -p ${DB_PORT} -d ${DB_NAME} << 'EOF'
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  filename TEXT NOT NULL UNIQUE,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
EOF

  # Iterate .sql files in lexical order
  for file in $(ls "${MIGRATIONS_DIR}"/*.sql 2>/dev/null | sort); do
    base=$(basename "$file")
    echo "Checking migration: ${base}"
    EXISTS=$(psql_as_postgres -p ${DB_PORT} -d ${DB_NAME} -tAc "SELECT 1 FROM schema_migrations WHERE filename='${base}'" || echo "")
    if [ "${EXISTS}" != "1" ]; then
      echo "Applying ${base} ..."
      if psql_as_postgres -p ${DB_PORT} -d ${DB_NAME} -f "$file"; then
        psql_as_postgres -p ${DB_PORT} -d ${DB_NAME} -c "INSERT INTO schema_migrations (filename) VALUES ('${base}')" >/dev/null
        echo "✓ Applied ${base}"
      else
        echo "✗ Failed applying ${base}"; exit 1
      fi
    else
      echo "Skipping ${base} (already applied)"
    fi
  done
else
  echo "No migrations directory found at ${MIGRATIONS_DIR}; skipping migrations."
fi

# Apply startup seeds (idempotent)
STARTUP_SQL="$(dirname "$0")/startup.sql"
if [ -f "${STARTUP_SQL}" ]; then
  echo "Applying startup seeds..."
  if ! psql_as_postgres -p ${DB_PORT} -d ${DB_NAME} -f "${STARTUP_SQL}"; then
    echo "✗ Failed to apply startup.sql"; exit 1
  fi
fi

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > "$(dirname "$0")/db_connection.txt"
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file
cat > "$(dirname "$0")/db_visualizer/postgres.env" << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""
echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"
echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat "$(dirname "$0")/db_connection.txt")"
