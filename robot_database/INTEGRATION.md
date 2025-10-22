# Database Integration Notes

- Default startup.sh starts Postgres on port 5000 with:
  - DB_NAME=myapp
  - DB_USER=appuser
  - DB_PASSWORD=dbuser123
- Migrations are applied automatically (migrations/*.sql) before accepting connections.
- Seeds from startup.sql are applied idempotently.
- Connection info is exported to robot_database/db_visualizer/postgres.env and written to db_connection.txt.

To connect backend to this database, configure its .env accordingly:
  POSTGRES_USER=appuser
  POSTGRES_PASSWORD=dbuser123
  POSTGRES_DB=myapp
  POSTGRES_HOST=localhost
  POSTGRES_PORT=5000
  POSTGRES_URL=postgresql+asyncpg://appuser:dbuser123@localhost:5000/myapp

If you run the DB on a different port/user/db, update the backend .env to match.
