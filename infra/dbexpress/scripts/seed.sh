#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: docker compose is not available." >&2
  exit 1
fi

if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
fi

DB_NAME="${MONGO_INITDB_DATABASE:-academyos}"
ROOT_USER="${MONGO_INITDB_ROOT_USERNAME:-}"
ROOT_PASS="${MONGO_INITDB_ROOT_PASSWORD:-}"

AUTH_ARGS=""
if [ -n "$ROOT_USER" ] && [ -n "$ROOT_PASS" ]; then
  AUTH_ARGS="-u $ROOT_USER -p $ROOT_PASS --authenticationDatabase admin"
fi

docker compose exec -T mongodb sh -lc "mongosh --quiet $AUTH_ARGS --eval '
const dbName = \"$DB_NAME\";
const dbRef = db.getSiblingDB(dbName);
const docs = [
  { title: \"MongoDB Basics\", level: \"beginner\", price: 0, tags: [\"mongodb\", \"database\"] },
  { title: \"Node + Mongo API\", level: \"intermediate\", price: 49, tags: [\"node\", \"api\", \"mongodb\"] },
  { title: \"Data Modeling\", level: \"advanced\", price: 99, tags: [\"schema\", \"design\"] }
];

docs.forEach(doc => {
  dbRef.courses.updateOne({ title: doc.title }, { \$set: doc }, { upsert: true });
});

print(\"Seeded/updated \" + docs.length + \" documents in \" + dbName + \".courses\");
'"

echo "Done."
