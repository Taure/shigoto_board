-module(shigoto_board_action_controller).
-moduledoc """
POST handlers for the board's controls (pause/resume a queue, retry/cancel a
job, redrive discarded jobs).

Each mutates Shigoto and returns a one-shot Datastar response: a normal
`{status, 200, ...}` reply whose body is an SSE-framed patch of the `#page`
region. Nova's built-in `handle_status` sends it, so the clicking client sees
the change immediately; other open clients converge on the next SSE poll. The
job actions carry the current filter/page as query params so the repaint shows
the same slice the user was looking at.
""".

-export([pause_queue/1, resume_queue/1, retry/1, cancel/1, redrive/1, redrive_all/1]).

pause_queue(Req) ->
    Queue = binding(~"queue", Req),
    _ = shigoto:pause_queue(Queue),
    oneshot(shigoto_board_page_controller:page_inner(queues, undefined)).

resume_queue(Req) ->
    Queue = binding(~"queue", Req),
    _ = shigoto:resume_queue(Queue),
    oneshot(shigoto_board_page_controller:page_inner(queues, undefined)).

retry(Req) ->
    job_action(Req, fun shigoto:retry/2).

cancel(Req) ->
    job_action(Req, fun shigoto:cancel/2).

redrive(Req) ->
    case job_id(Req) of
        {ok, Id} ->
            _ = shigoto:retry(shigoto_config:pool(), Id),
            oneshot(shigoto_board_page_controller:page_inner(dlq, undefined));
        error ->
            {status, 400}
    end.

redrive_all(_Req) ->
    _ = shigoto:retry_by(shigoto_config:pool(), #{state => ~"discarded"}),
    oneshot(shigoto_board_page_controller:page_inner(dlq, undefined)).

%% ---------------------------------------------------------------------------
%% internal
%% ---------------------------------------------------------------------------

job_action(Req, Fun) ->
    case job_id(Req) of
        {ok, Id} ->
            _ = Fun(shigoto_config:pool(), Id),
            Filters = shigoto_board_page_controller:filters_from_qs(cowboy_req:parse_qs(Req)),
            oneshot(shigoto_board_page_controller:page_inner(jobs, Filters));
        error ->
            {status, 400}
    end.

job_id(Req) ->
    try
        {ok, binary_to_integer(binding(~"id", Req))}
    catch
        _:_ -> error
    end.

binding(Key, Req) ->
    maps:get(Key, maps:get(bindings, Req, #{}), ~"").

oneshot(Inner) ->
    Frame = datastar:patch_elements(Inner, #{selector => ~"#page", mode => inner}),
    {status, 200, maps:from_list(datastar:sse_headers()), iolist_to_binary(Frame)}.
