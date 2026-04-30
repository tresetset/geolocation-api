# Architecture Decision Records

## PostgreSQL

PostgreSQL chosen for its native `inet`/`cidr` types and indexing — well-suited for storing and querying URLs and IP addresses in the geolocation data model.

## Authentication

All endpoints require authentication — there are no public routes. Currently a static API key passed in the `X-Api-Key` header. Simple to implement and sufficient for MVP. Target: replace with JWT (`Authorization: Bearer <token>`) before production to support per-user identity, token expiry, and revocation.

## Service objects for business logic

Business logic in `app/services/`, controllers stay thin. Dependencies injected via constructor for testability. `before_action` only for authentication.

## RESTful API with JSON:API serialization

The API follows REST conventions. Responses conform to the [JSON:API](https://jsonapi.org) spec using the `jsonapi-serializer` gem. Serializers live in `app/serializers/`. Explicit attribute declaration prevents accidental data leakage.

## Geolocation provider abstraction

The current provider is [ipstack](https://ipstack.com). The geolocation module communicates with it through an adapter abstraction (`GeolocationProvider`), not directly. The concrete provider is injected into `GeolocationService` via constructor — swapping providers (e.g. ipstack → MaxMind) requires only a new adapter class implementing `#lookup(ip)` with no changes to business logic.

`GeolocationProviderFactory.build` is intentionally hardcoded to `IpstackProvider`. This is a conscious MVP decision — there is currently no need to switch providers at runtime. If a second adapter is added in the future, the factory is the single place to introduce selection logic (e.g. driven by a `GEOLOCATION_PROVIDER` env var). The abstraction is already in place; the switching mechanism can be added when it is needed.

## Geolocation model schema

| column | type | constraints |
|---|---|---|
| `id` | uuid | PK, generated via `before_create` |
| `ip` | inet | not null, unique |
| `url_hostname` | string | nullable — hostname extracted from the query when input was not a bare IP (e.g. `google.com` for `https://google.com/path`); last-write wins |
| `ip_type` | string | not null — `"ipv4"` or `"ipv6"` as returned by provider |
| `country_code` | string(2) | nullable — ISO 3166-1 alpha-2 |
| `city` | string | nullable |
| `latitude` | decimal(9,6) | not null — range -90..90 |
| `longitude` | decimal(9,6) | not null — range -180..180 |
| `created_at` | timestamp | not null |
| `updated_at` | timestamp | not null |

`decimal(9,6)` gives 6 decimal places of precision (~11cm at the equator, WGS84 GPS standard). Stored as PostgreSQL `numeric` to avoid floating-point rounding errors. Serialized as JSON `number` (float, 6 decimal places) — e.g. `37.386051`, not `"37.386051"`. The serializer explicitly calls `.to_f.round(6)` to ensure consistent numeric output regardless of how the provider returns the value.

`ip` uses PostgreSQL `inet` — native type with built-in validation and efficient indexing. `ip_type`, `latitude`, and `longitude` are required — if the provider cannot return them the record is not saved. `country_code` and `city` remain nullable as some IPs resolve coordinates but lack city-level data.

## Endpoints

Four endpoints, all under `/api/v1/geolocations`, all authenticated via `X-Api-Key`.

| method | path | description |
|---|---|---|
| POST | `/api/v1/geolocations` | create or refresh geolocation by IP/URL/hostname |
| GET | `/api/v1/geolocations` | paginated list; `?filter[query]=` filters by IP/URL/hostname |
| GET | `/api/v1/geolocations/:query` | retrieve single geolocation by IP, URL, or hostname |
| DELETE | `/api/v1/geolocations/:query` | delete geolocation by IP, URL, or hostname |

`GET /api/v1/geolocations` returns a JSON:API collection with Pagy metadata (`page`, `per_page`, `total`) and top-level `links` (`first`, `last`, `next`, `prev`) as required by the JSON:API spec. Filtering uses the spec-reserved `filter` key: `?filter[query]=<ip|url|hostname>` resolves to an IP and returns 0 or 1 result as an array. Pagination links preserve any active filter parameter. Page overflow returns `400`.

**GET collection status codes:**

| situation | status | code |
|---|---|---|
| success | 200 | — |
| missing/invalid API key | 401 | `unauthorized` |
| page overflow | 400 | — |

**GET single status codes:**

| situation | status | code |
|---|---|---|
| found | 200 | — |
| missing/invalid API key | 401 | `unauthorized` |
| not found (valid IP, no record) | 404 | `not_found` |
| invalid IP/URL | 422 | `invalid_query` |
| private/reserved IP | 422 | `reserved_ip_address` |
| unresolvable host | 422 | `unresolvable_host` |

**DELETE status codes:**

| situation | status | code |
|---|---|---|
| deleted | 204 | — |
| missing/invalid API key | 401 | `unauthorized` |
| not found (valid IP, no record) | 404 | `not_found` |
| invalid IP/URL | 422 | `invalid_query` |
| private/reserved IP | 422 | `reserved_ip_address` |
| unresolvable host | 422 | `unresolvable_host` |

## POST /geolocations — POST vs PUT for upsert

`POST /api/v1/geolocations` behaves as an upsert: it creates or refreshes. Strictly, POST is non-idempotent, but in practice two identical calls produce the same record — making the behaviour idempotent. A `PUT /api/v1/geolocations/:ip` would be more semantically correct (PUT is idempotent by definition). POST-upsert was chosen because the `:query` input is not a stable resource identifier — it can be a URL or hostname that needs server-side resolution. Forcing the client to supply a bare IP as a URL segment would push resolution logic out of the API. POST with a body-level `query` attribute is a natural fit for this "lookup and store" intent and is a widely recognised convention for search/import-style endpoints.

## POST /geolocations — `query` as a virtual input attribute

The `query` field in the POST request body is not a stored resource attribute — it is a transient input that the server resolves to an IP address before persisting. Strictly speaking, JSON:API expects `attributes` in a POST body to mirror the resource's own fields. `query` intentionally deviates from this: it is an input DTO rather than a resource field.

This is a deliberate architectural decision driven by usability. The alternative — requiring the client to pre-resolve a hostname or strip a URL down to a bare IP before calling the API — would push DNS resolution and validation logic to every consumer of the API. Accepting `query` server-side keeps that complexity in one place, makes the API self-contained, and is a widely understood convention (similar to search or lookup endpoints across many REST APIs). The deviation is minimal and the intent is immediately readable.

## DELETE /geolocations/:query — identifier is the query, not a UUID

`DELETE /api/v1/geolocations/:query` uses the same query resolution as `POST` — the `:query` segment accepts a bare IP, URL, or hostname, resolves it server-side to an IP address via `QueryParser`, then finds and deletes the matching record. This satisfies the requirement to delete geolocation data "on the basis of ip address or URL" without requiring the client to know the record's internal UUID.

The route constraint `constraints: { id: /[^\/]+/ }` is set so that IP addresses containing dots (e.g. `1.1.1.1`) are not misinterpreted as a format suffix by Rails.

`GET /api/v1/geolocations/:query` and `DELETE /api/v1/geolocations/:query` both use the same query resolution as `POST` — the `:query` segment accepts a bare IP, URL, or hostname. This keeps the API consistent: all write and read operations on a single resource use the same natural identifier (the IP/URL), not an internal UUID. The UUID is still exposed in the response body and `Location` header for clients that want a stable, opaque reference.

## POST /geolocations — endpoint contract

`POST /api/v1/geolocations` accepts a single `query` attribute (bare IP, URL, or hostname). If the IP has not been seen before, the record is created and `201 Created` is returned. If the IP already exists, geo data is refreshed from the provider and `200 OK` is returned. This upsert design keeps the API idempotent from the caller's perspective — repeated calls are safe and always return fresh data. On `201`, the `Location` header is set to `/api/v1/geolocations/<ip>` (e.g. `Location: /api/v1/geolocations/8.8.8.8`) — pointing to the `GET /:query` endpoint which uses the same IP-based identifier.

**Request:**
```json
{
  "data": {
    "type": "geolocations",
    "attributes": {
      "query": "8.8.8.8"
    }
  }
}
```

**Response (201 Created):**
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
      "latitude": 37.386,
      "longitude": -122.0838,
      "created_at": "2026-04-30T10:15:00Z",
      "updated_at": "2026-04-30T10:15:00Z"
    },
    "links": {
      "self": "/api/v1/geolocations/8.8.8.8"
    }
  },
  "jsonapi": { "version": "1.1" }
}
```

**Error response:**
```json
{
  "errors": [
    {
      "status": "422",
      "code": "reserved_ip_address",
      "title": "Reserved IP address",
      "source": { "pointer": "/data/attributes/query" }
    }
  ]
}
```

**Status codes:**

| situation | status | code |
|---|---|---|
| first create | 201 | — |
| refresh | 200 | — |
| missing/invalid API key | 401 | `unauthorized` |
| wrong Content-Type | 415 | `unsupported_media_type` |
| missing query | 400 | `missing_parameter` |
| invalid IP/URL | 422 | `invalid_query` |
| private/reserved IP | 422 | `reserved_ip_address` |
| unresolvable host | 422 | `unresolvable_host` |
| provider timeout/5xx | 503 | `provider_unavailable` |
| provider rate limit | 503 | `provider_rate_limited` |
| provider success: false | 502 | `provider_error` |

## Concurrent upserts — race condition handling

`GeolocationService` uses `find_or_initialize_by` inside a transaction. Under concurrent requests for the same IP, two threads can both reach `find_or_initialize_by`, both see no existing record, and both attempt an INSERT — the second INSERT hits the unique index on `ip` and raises `ActiveRecord::RecordNotUnique`. The service rescues this exception inside the transaction block, re-fetches the now-existing record, and updates it, returning `:ok`. The caller receives correct data and no 500 error.

## Provider error handling — timeouts, rate limits, retries

HTTP calls to the provider use explicit timeouts (5s connect, 10s read) to avoid blocking request threads. No automatic retry logic — retrying on rate limit (ipstack error code 104) would accelerate quota exhaustion, and retrying on transient errors (timeout, 5xx) adds complexity without clear benefit at MVP scale. Callers receive a `503` and may retry at their discretion. The upsert design naturally reduces provider call volume — the same IP is only re-queried on an explicit refresh, not on every request.
