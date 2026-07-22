# MongoDB + Mongo Express (Docker Compose)

Run a local MongoDB + Mongo Express stack with one command.

## What you get

- **MongoDB 7** container
- **Mongo Express** web UI
- Persistent Docker volume (`mongodb_data`)
- MongoDB **healthcheck** + Mongo Express waits for healthy DB
- Optional auth mode via environment variables

---

## Prerequisites

- Docker
- Docker Compose (`docker compose`)

```bash
docker --version
docker compose version
```

---

## Quick start

```bash
cp .env.example .env
docker compose up -d
```

Open Mongo Express:
- URL: http://localhost:8081
- Username: `webuser`
- Password: `webpass`

Check status:

```bash
docker compose ps
```

---

## Environment variables

Compose reads `.env` if present. Defaults exist in `docker-compose.yml`.

| Variable | Default | Description |
|---|---|---|
| `MONGO_CONTAINER_NAME` | `academyos-mongodb` | MongoDB container name |
| `MONGO_PORT` | `27017` | Host port mapped to MongoDB |
| `MONGO_INITDB_DATABASE` | `academyos` | Default app database |
| `MONGO_INITDB_ROOT_USERNAME` | _(empty)_ | Optional MongoDB root user |
| `MONGO_INITDB_ROOT_PASSWORD` | _(empty)_ | Optional MongoDB root password |
| `MONGO_EXPRESS_CONTAINER_NAME` | `mongo-express` | Mongo Express container name |
| `MONGO_EXPRESS_PORT` | `8081` | Host port mapped to Mongo Express |
| `ME_CONFIG_MONGODB_URL` | `mongodb://mongodb:27017/` | Mongo connection URL used by Mongo Express |
| `ME_CONFIG_BASICAUTH_USERNAME` | `webuser` | Mongo Express UI login username |
| `ME_CONFIG_BASICAUTH_PASSWORD` | `webpass` | Mongo Express UI login password |

---

## Seed sample data (one command)

Use the included script:

```bash
./scripts/seed.sh
```

What it does:
- inserts/updates sample `courses` documents
- uses `MONGO_INITDB_DATABASE`
- automatically uses root auth flags if auth vars are set

Verify:

```bash
docker compose exec mongodb mongosh --quiet --eval '
const dbName = process.env.MONGO_INITDB_DATABASE || "academyos";
printjson(db.getSiblingDB(dbName).courses.find().toArray());
'
```

---

## Optional: enable MongoDB authentication

1. In `.env`, set:

```env
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=change-me
ME_CONFIG_MONGODB_URL=mongodb://admin:change-me@mongodb:27017/?authSource=admin
```

2. Recreate containers so MongoDB starts with auth config:

```bash
docker compose down
docker compose up -d
```

> If you already had data in the volume, and auth behavior is not what you expect, do a clean reset with `docker compose down -v` and start again.

---

## Useful commands

```bash
# logs
docker compose logs -f

# restart
docker compose restart

# stop
docker compose down

# hard reset (deletes DB data)
docker compose down -v
```

---

## Troubleshooting

### Port already in use

Set custom ports in `.env`:

```env
MONGO_PORT=27018
MONGO_EXPRESS_PORT=8082
```

Then:

```bash
docker compose down
docker compose up -d
```

### Mongo Express cannot connect

- Check DB health/status: `docker compose ps`
- Check `ME_CONFIG_MONGODB_URL` in `.env`
- Check logs: `docker compose logs mongo-express`

---

## Project files

- `docker-compose.yml` → service definitions + healthcheck
- `.env.example` → sample env config
- `scripts/seed.sh` → one-command sample data seed
- `README.md` → setup and usage guide
