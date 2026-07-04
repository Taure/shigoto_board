-module(shigoto_board_router).
-behaviour(nova_router).

-export([routes/1]).

%% All pages, the per-page SSE streams, the queue/job actions and the static
%% assets run on the host's Nova listener under the configured prefix. The
%% /sse/:page route returns {stream, ...}, held open by shigoto_board_sse
%% (see that module + novaframework/nova#387).
routes(_Env) ->
    [
        #{
            prefix => binary_to_list(shigoto_board:prefix()),
            security => false,
            routes => [
                {"/", fun shigoto_board_page_controller:index/1, #{methods => [get]}},
                {"/queues", fun shigoto_board_page_controller:queues/1, #{methods => [get]}},
                {"/workers", fun shigoto_board_page_controller:workers/1, #{methods => [get]}},
                {"/jobs", fun shigoto_board_page_controller:jobs/1, #{methods => [get]}},
                {"/batches", fun shigoto_board_page_controller:batches/1, #{methods => [get]}},
                {"/cron", fun shigoto_board_page_controller:cron/1, #{methods => [get]}},
                {"/failures", fun shigoto_board_page_controller:failures/1, #{methods => [get]}},
                {"/queues/:queue/pause", fun shigoto_board_action_controller:pause_queue/1, #{
                    methods => [post]
                }},
                {"/queues/:queue/resume", fun shigoto_board_action_controller:resume_queue/1, #{
                    methods => [post]
                }},
                {"/jobs/:id/retry", fun shigoto_board_action_controller:retry/1, #{
                    methods => [post]
                }},
                {"/jobs/:id/cancel", fun shigoto_board_action_controller:cancel/1, #{
                    methods => [post]
                }},
                {"/sse/:page", fun shigoto_board_sse:stream/1, #{methods => [get]}},
                {"/heartbeat", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/[...]", "static/assets"}
            ]
        }
    ].
