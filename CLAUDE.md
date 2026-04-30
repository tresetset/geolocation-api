# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bin/setup          # install deps, prepare DB, clear logs/tmp
rails server       # start development server (port 3000)
bin/rubocop        # lint
bin/brakeman       # Rails security static analysis
bin/bundler-audit  # gem vulnerability scan
bin/ci             # full CI check (security + lint)
```

```bash
bundle exec rspec                              # full test suite
bundle exec rspec spec/path/to/file_spec.rb   # single spec file
```

## Architecture

Rails 8.1.3 API-only (`config.api_only = true`). Three PostgreSQL databases in production: primary, cache (Solid Cache), and queue (Solid Queue).

**Controllers** are thin — business logic lives in models and service objects.

- Base: `Api::V1::ApplicationController < ApplicationController` (includes `Authenticatable`)
- All controllers in `app/controllers/api/v1/` inherit from `Api::V1::ApplicationController`

**Concerns** (`app/controllers/concerns/`):
- `Authenticatable` — included in `Api::V1::ApplicationController` (applies to all endpoints); validates static API key from `X-Api-Key` header → 401 if missing or invalid. There are no public endpoints. Target: replace with JWT before production.

**Service Objects** (`app/services/`): accept dependencies via constructor (Dependency Inversion).
- `JsonWebToken` — encodes/decodes JWT tokens
- `OcrService` — calls Gemini 2.5 Flash to extract word pairs from image

**Serialization**: `jsonapi-serializer` serializers in `app/serializers/` — JSON:API spec compliant

**Routes** — all endpoints under `/api/v1/` prefix (`config/routes.rb`):
```ruby
namespace :api do
  namespace :v1 do
    post 'auth/register', to: 'auth#register'
    post 'auth/login',    to: 'auth#login'
  end
end
```

## HTTP Status Codes

| Code | Meaning | When |
|------|---------|------|
| 200 | OK | success |
| 201 | Created | resource created |
| 400 | Bad Request | `ArgumentError`, page overflow, missing required params |
| 401 | Unauthorized | JWT missing or invalid |
| 403 | Forbidden | user doesn't own the resource |
| 404 | Not Found | resource doesn't exist |
| 422 | Unprocessable Content | model validation errors |

## Pagination (Pagy)

`Pagy::Backend` included in `ApplicationController`. Default: `per_page: 20`, `overflow: :exception` (returns 400 on page overflow).

Response shapes:
```json
{ "data": [...], "meta": { "page": 1, "per_page": 20, "total": 100 } }  // paginated
{ "data": [...] }  // unpaginated
```

## Conventions

- **Primary keys**: UUID v7, generated in `ApplicationRecord` via `before_create`
- **Dates**: ISO 8601
- **Auth**: static API key in `X-Api-Key` header (MVP); target: JWT before production
- **CORS**: `origins '*'` is intentional for MVP — change before production

## Naming Conventions

Column names must not repeat the model name — the model already provides the namespace. Use `code` not `language_code` on `Language`, `name` not `language_name`, etc.

## API Standards

- Run `bundle exec rubocop -A` after generating or modifying any Ruby files
- Use `Rails.application.credentials` or `ENV` variables — never hardcode secrets
- Never nest relationships more than 1 level deep in responses (avoid N+1)

## Code Style

Ruby style is enforced by RuboCop (omakase). For any JS/TS files: single quotes, trailing commas everywhere, no parens around single arrow function args.

## Rules

- Never put business logic in controllers
- Never use `before_action` for anything other than authentication

## Code Quality

- **SOLID** — Single Responsibility (each class/function does one thing); Dependency Inversion (depend on abstractions, not concrete implementations)
- **DRY** — extract shared behaviour into service objects, concerns, or helpers
- **Constants** over magic numbers/strings
- **Edge cases** — cover boundary conditions: empty data, network errors, race conditions
- **Tests** — all new business logic must be covered by tests
