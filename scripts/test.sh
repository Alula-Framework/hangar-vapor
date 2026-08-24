#!/usr/bin/env bash
#
# Runs the suite against a throwaway Postgres.
#
# These tests are about a real connection pool inside a real Vapor
# application; there is nothing worth asserting against a fake, so they skip
# without a database — and a skipped suite is not a passing one. Rather than
# asking a contributor to assemble the right environment, this starts what
# is needed, runs everything, and cleans up.
#
#   ./scripts/test.sh                 # everything
#   ./scripts/test.sh --filter Foo    # arguments pass through to swift test
#
# Set FLIGHT_KEEP_SERVERS=1 to leave the container running between runs.
#
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null; then
  echo "docker is needed to start the test database." >&2
  echo "Already have one? Export HANGAR_VAPOR_TEST_DATABASE_URL and run swift test directly." >&2
  exit 1
fi

pg_name="hangar-vapor-test-postgres"
pg_port=${FLIGHT_TEST_PG_PORT:-55499}

cleanup() {
  if [ "${FLIGHT_KEEP_SERVERS:-0}" != "1" ]; then
    docker rm -f "$pg_name" >/dev/null 2>&1 || true
  fi
}
# No `exec` below: it would replace this shell and the trap would never run,
# leaking the container.
trap cleanup EXIT

docker rm -f "$pg_name" >/dev/null 2>&1 || true
docker run -d --name "$pg_name" \
  -e POSTGRES_PASSWORD=flight -e POSTGRES_DB=hangar_vapor_test \
  -p "$pg_port":5432 postgres:16-alpine >/dev/null

printf 'waiting for postgres'
for _ in $(seq 60); do
  if docker exec "$pg_name" pg_isready -U postgres >/dev/null 2>&1; then
    echo " ready"
    break
  fi
  printf '.'
  sleep 1
done

export HANGAR_VAPOR_TEST_DATABASE_URL="postgres://postgres:flight@127.0.0.1:$pg_port/hangar_vapor_test"
./CI/run-tests.sh "$@"
