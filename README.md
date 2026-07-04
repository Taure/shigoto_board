# shigoto_board

Live dashboard for the [Shigoto](https://github.com/Taure/shigoto) background job system. Built with [Nova](https://github.com/novaframework/nova) and [Datastar](https://github.com/starfederation/datastar) - server-rendered HTML with live SSE updates, no build step and no client framework.

## Installation

Add to your `rebar.config`:

```erlang
{deps, [
    {shigoto_board, {git, "https://github.com/Taure/shigoto_board.git", {branch, "main"}}}
]}.
```

## Configuration

Mount as a Nova app in `sys.config`:

```erlang
{my_app, [
    {nova_apps, [
        {shigoto_board, #{prefix => "/jobs"}}
    ]}
]},
{shigoto_board, [
    {prefix, "/jobs"},
    {refresh_ms, 2000}
]}
```

- `prefix` - URL prefix the board is mounted under (default `/shigoto`).
- `refresh_ms` - how often the live regions repaint (default `2000`).

## Pages

- **Overview** - Global job counts, queue health, stale jobs
- **Queues** - Per-queue stats with pause/resume controls
- **Workers** - Per-worker statistics
- **Jobs** - Searchable job list with filter, pagination, expandable detail, retry/cancel
- **Batches** - Active batch monitoring
- **Cron** - Configured cron entries
- **Failures** - Stale (zombie) jobs with heartbeat detail

## How it works

Each page server-renders a first-paint snapshot, then a `data-init` SSE stream
(`/<prefix>/sse/:page`) repaints the `#page` region every `refresh_ms`. The
jobs filter/page state rides as query params on the stream URL, so each viewer
polls exactly the slice they are looking at. Mutations (pause/resume, retry,
cancel) post back and return a one-shot Datastar patch. `datastar.js` is served
self-hosted under `/<prefix>/assets/js/` behind a strict same-origin CSP.
