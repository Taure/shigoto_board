# shigoto_board

Live dashboard for the [Shigoto](https://github.com/Taure/shigoto) background job system. Built with [Nova](https://github.com/novaframework/nova) and [Arizona](https://github.com/novaframework/arizona_core).

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
    {prefix, "/jobs"}
]}
```

## Pages

- **Overview** — Global job counts, queue health, stale jobs
- **Queues** — Per-queue stats with pause/resume controls
- **Workers** — Per-worker statistics
- **Jobs** — Searchable job list with filter/retry/cancel
- **Batches** — Active batch monitoring
- **Failures** — Recent failures with error details and retry
