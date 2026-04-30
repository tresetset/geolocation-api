# Geolocation API

REST API for storing and querying geolocation data by IP address or URL. Geolocation data is fetched from [ipstack](https://ipstack.com). Responses follow the [JSON:API](https://jsonapi.org) spec. All endpoints require an API key.

See [ADR.md](ADR.md) for key technical decisions.

## Requirements

- Ruby 4.0.2
- PostgreSQL

or

- Docker

## Installation

**Local:**
```bash
cp .env.example .env
# edit .env:
#   API_KEY           — any secret string of your choice
#   IPSTACK_ACCESS_KEY — get a free key at https://ipstack.com (free plan is sufficient)
bundle install
bin/rails db:prepare db:seed
```

**Docker:**
```bash
cp .env.example .env
# edit .env:
#   API_KEY           — any secret string of your choice
#   IPSTACK_ACCESS_KEY — get a free key at https://ipstack.com (free plan is sufficient)
docker compose up --build
```

## Running

**Local:**
```bash
rails server                                         # http://localhost:3000
```

**Docker:**
```bash
docker compose up          # http://localhost:3000
docker compose down        # stop
docker compose down -v     # stop + delete database
```

**Linting & security:**
```bash
bundle exec rubocop            # lint
bundle exec rubocop -A         # lint with autocorrect
bundle exec brakeman           # security static analysis
bundle exec bundler-audit      # gem vulnerability scan
```

**Tests:**
```bash
bundle exec rspec                                    # full test suite
bundle exec rspec spec/path/to/file_spec.rb          # single spec file
```

**Tests (Docker):**
```bash
docker compose run --rm app bundle exec rspec
docker compose run --rm app bundle exec rspec spec/path/to/file_spec.rb
```

### VCR cassettes

HTTP interactions with external providers (ipstack) are recorded as VCR cassettes in `spec/cassettes/` and committed to the repo. Tests replay cassettes without hitting the network.

To re-record a cassette, delete it and run the test with a valid API key:
```bash
IPSTACK_ACCESS_KEY=your_key bundle exec rspec spec/requests/api/v1/geolocations_spec.rb
```

The access key is automatically stripped from cassette files before saving.

## Usage

All requests require the `X-Api-Key` header set to the value of `API_KEY` from your `.env`.

**Create or refresh a geolocation:**
```bash
curl -X POST http://localhost:3000/api/v1/geolocations \
  -H "Content-Type: application/vnd.api+json" \
  -H "Accept: application/vnd.api+json" \
  -H "X-Api-Key: your_secret_api_key" \
  -d '{
    "data": {
      "type": "geolocations",
      "attributes": {
        "query": "8.8.8.8"
      }
    }
  }'
```

`query` accepts a bare IP address (`8.8.8.8`, `2001:4860:4860::8888`), a full URL (`https://google.com`), or a hostname (`cloudflare.com`).

**Response — 201 Created (first request):**
```json
{
  "data": {
    "type": "geolocations",
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "attributes": {
      "ip": "8.8.8.8",
      "url_hostname": null,
      "ip_type": "ipv4",
      "country_code": "US",
      "city": "Mountain View",
      "latitude": 37.386051,
      "longitude": -122.083855,
      "created_at": "2026-04-30T10:15:00Z",
      "updated_at": "2026-04-30T10:15:00Z"
    },
    "links": {
      "self": "/api/v1/geolocations/550e8400-e29b-41d4-a716-446655440000"
    }
  },
  "jsonapi": { "version": "1.1" }
}
```

On `201 Created` the response includes `Location: /api/v1/geolocations/8.8.8.8`.

**Response — 200 OK (same IP again):** identical shape, same `id` and `created_at`, refreshed `updated_at` and geo data.

**List all geolocations (paginated):**
```bash
curl "http://localhost:3000/api/v1/geolocations" \
  -H "Accept: application/vnd.api+json" \
  -H "X-Api-Key: your_secret_api_key"
```

```json
{
  "data": [
    {
      "type": "geolocations",
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "attributes": { "ip": "8.8.8.8", "ip_type": "ipv4", "country_code": "US", "..." : "..." },
      "links": { "self": "/api/v1/geolocations/550e8400-e29b-41d4-a716-446655440000" }
    }
  ],
  "meta": { "page": 1, "per_page": 20, "total": 1 },
  "links": {
    "first": "http://localhost:3000/api/v1/geolocations?page=1",
    "last":  "http://localhost:3000/api/v1/geolocations?page=1",
    "next":  null,
    "prev":  null
  },
  "jsonapi": { "version": "1.1" }
}
```

**Filter by IP or URL:**
```bash
curl -g "http://localhost:3000/api/v1/geolocations?filter[query]=8.8.8.8" \
  -H "Accept: application/vnd.api+json" \
  -H "X-Api-Key: your_secret_api_key"
```

Returns the same collection shape with 0 or 1 result.

**Get geolocation by IP, URL, or hostname:**
```bash
curl http://localhost:3000/api/v1/geolocations/8.8.8.8 \
  -H "Accept: application/vnd.api+json" \
  -H "X-Api-Key: your_secret_api_key"

# or by hostname
curl http://localhost:3000/api/v1/geolocations/dns.google \
  -H "Accept: application/vnd.api+json" \
  -H "X-Api-Key: your_secret_api_key"
```

Returns `200 OK` with single-resource JSON:API shape, `404` if not found, or `422` for invalid/private IPs.

**Delete geolocation by IP, URL, or hostname:**
```bash
curl -X DELETE http://localhost:3000/api/v1/geolocations/8.8.8.8 \
  -H "X-Api-Key: your_secret_api_key"

# or by hostname (resolved to IP server-side)
curl -X DELETE http://localhost:3000/api/v1/geolocations/google.com \
  -H "X-Api-Key: your_secret_api_key"
```

Returns `204 No Content`. Returns `404` if no record exists for that IP. Returns `422` for invalid or private IPs.

## Endpoints

All endpoints require the `X-Api-Key` header. All responses and errors conform to the JSON:API spec.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/geolocations` | Create or refresh a geolocation for an IP, URL, or hostname |
| `GET` | `/api/v1/geolocations` | Paginated list; filter by `?query=` (IP, URL, or hostname) |
| `GET` | `/api/v1/geolocations/:query` | Retrieve a single geolocation by IP, URL, or hostname |
| `DELETE` | `/api/v1/geolocations/:query` | Delete a geolocation by IP, URL, or hostname |

### Status codes

| Code | Meaning |
|------|---------|
| 200 | OK — existing record returned (GET) or refreshed (POST) |
| 201 | Created — new geolocation record created |
| 204 | No Content — record deleted |
| 400 | Bad Request — missing required parameter or page number out of range |
| 401 | Unauthorized — missing or invalid `X-Api-Key` |
| 404 | Not Found — record does not exist |
| 415 | Unsupported Media Type — `Content-Type` must be `application/vnd.api+json` |
| 422 | Unprocessable Content — invalid IP/URL, private/reserved address, or unresolvable hostname |
| 503 | Service Unavailable — geolocation provider is unreachable or rate-limited |

## Tests

The test suite covers all endpoints (success and error paths), the model, and all service objects.

```bash
bundle exec rspec                    # full suite
bundle exec rspec spec/requests/     # request/integration specs
bundle exec rspec spec/models/       # model specs
bundle exec rspec spec/services/     # service specs
```

HTTP interactions with ipstack are recorded as VCR cassettes in `spec/cassettes/` and committed to the repo. The suite runs fully offline — no API key required.
