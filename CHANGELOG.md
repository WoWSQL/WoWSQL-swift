# Changelog

All notable changes to the WowSQL Swift SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.9.0] - 2026-08-20

### Added - Realtime

- `client.realtime.subscribe()` for Postgres `INSERT` / `UPDATE` / `DELETE` (and `*`)
- WebSocket auth: `wss://<project>/realtime/v1/websocket?apikey=<anon or service_role key>`
- Auto-reconnect after disconnect; unsubscribe / disconnect clean local and server state
- `client.realtime.channel(name)` — ephemeral broadcast (`send`) and presence (`track` / `presenceState`)

### Documentation

- README realtime section
