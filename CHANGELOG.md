# Changelog

All notable changes to the WowSQL Swift SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.9.3] - 2026-10-10

### Docs - CAPTCHA bring-your-own widget
- README: create a Cloudflare Turnstile widget for your app domain and paste site key + secret in Attack Protection. WoWSQL does not provide a shared widget. `GET /auth/v1/settings` returns your `captcha.site_key`.

## [3.9.2] - 2026-10-10

### Added - Optional Turnstile captcha
- Optional captcha token on signup, login, forgot password, OTP send, magic link, and resend verification
- Existing calls without a token remain unchanged

## [3.9.1] - 2026-10-07

### Added - Phone OTP (SMS)
- `sendOtp` / `verifyOtp` (and language equivalents) accept either **email** or **phone** (exactly one)
- Existing email OTP call sites remain backward compatible


## [3.9.0] - 2026-08-20

### Added - Realtime

- `client.realtime.subscribe()` for Postgres `INSERT` / `UPDATE` / `DELETE` (and `*`)
- WebSocket auth: `wss://<project>/realtime/v1/websocket?apikey=<anon or service_role key>`
- Auto-reconnect after disconnect; unsubscribe / disconnect clean local and server state
- `client.realtime.channel(name)` â€” ephemeral broadcast (`send`) and presence (`track` / `presenceState`)

### Documentation

- README realtime section
