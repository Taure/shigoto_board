-module(shigoto_board_html_tests).
-include_lib("eunit/include/eunit.hrl").

%% ---------------------------------------------------------------------------
%% sample data (shapes mirror shigoto_dashboard returns)
%% ---------------------------------------------------------------------------

counts() ->
    #{
        available => 42,
        executing => 5,
        retryable => 2,
        completed => 1000,
        discarded => 3,
        cancelled => 1
    }.

queues() ->
    [#{queue => ~"default", available => 42, executing => 5, retryable => 2}].

workers() ->
    [
        #{
            worker => ~"my_worker",
            total => 100,
            available => 1,
            executing => 2,
            completed => 90,
            retryable => 1,
            discarded => 6
        }
    ].

jobs() ->
    [
        #{
            id => 7,
            worker => ~"my_worker",
            queue => ~"default",
            state => ~"retryable",
            attempt => 2,
            max_attempts => 3,
            inserted_at => {{2026, 7, 4}, {10, 0, 0}},
            args => ~"{\"x\":1}",
            meta => ~"{}",
            errors => [#{~"attempt" => 1, ~"error" => ~"boom"}]
        }
    ].

batches() ->
    [
        #{
            id => 1,
            callback_worker => my_cb,
            state => ~"active",
            total_jobs => 10,
            completed_jobs => 4,
            discarded_jobs => 1
        }
    ].

stale() ->
    [
        #{
            id => 9,
            worker => ~"w",
            queue => ~"default",
            attempt => 3,
            heartbeat_at => {{2026, 7, 4}, {9, 0, 0}}
        }
    ].

filters() ->
    #{filter_state => ~"retryable", filter_queue => ~"", filter_worker => ~"", page => 1}.

render(IoData) ->
    iolist_to_binary(IoData).

has(Bin, Needle) ->
    binary:match(Bin, Needle) =/= nomatch.

%% ---------------------------------------------------------------------------
%% tests
%% ---------------------------------------------------------------------------

overview_renders_stats_and_tables_test() ->
    B = render(shigoto_board_html:overview_html(counts(), queues(), workers(), 1)),
    ?assert(has(B, ~"stat-value")),
    ?assert(has(B, ~"1000")),
    ?assert(has(B, ~"my_worker")),
    ?assert(has(B, ~"stale job(s)")).

overview_no_stale_hides_alert_test() ->
    B = render(shigoto_board_html:overview_html(counts(), queues(), workers(), 0)),
    ?assertNot(has(B, ~"stale job(s)")).

queues_render_action_buttons_test() ->
    B = render(shigoto_board_html:queues_html(queues())),
    ?assert(has(B, ~"/queues/default/pause")),
    ?assert(has(B, ~"/queues/default/resume")),
    ?assert(has(B, ~"data-on-click")).

workers_empty_state_test() ->
    B = render(shigoto_board_html:workers_html([])),
    ?assert(has(B, ~"No worker data available")).

jobs_render_filter_and_actions_test() ->
    B = render(shigoto_board_html:jobs_html(jobs(), filters())),
    ?assert(has(B, ~"filter-bar")),
    ?assert(has(B, ~"<form")),
    ?assert(has(B, ~"/jobs/7/retry")),
    ?assert(has(B, ~"/jobs/7/cancel")),
    %% retryable state pre-selected in the filter dropdown
    ?assert(has(B, ~"value=\"retryable\" selected")),
    %% row-expand uses a client-only signal, detail row is present
    ?assert(has(B, ~"$_open_7")),
    ?assert(has(B, ~"detail-row")).

jobs_empty_state_test() ->
    B = render(shigoto_board_html:jobs_html([], filters())),
    ?assert(has(B, ~"No jobs match the current filters")).

batches_render_progress_test() ->
    B = render(shigoto_board_html:batches_html(batches())),
    ?assert(has(B, ~"bar-fill")),
    %% (4 + 1) / 10 = 50%
    ?assert(has(B, ~"width:50%")),
    ?assert(has(B, ~"my_cb")).

cron_render_test() ->
    B = render(shigoto_board_html:cron_html([{~"nightly", ~"0 0 * * *", some_worker, []}])),
    ?assert(has(B, ~"nightly")),
    ?assert(has(B, ~"some_worker")).

cron_empty_test() ->
    B = render(shigoto_board_html:cron_html([])),
    ?assert(has(B, ~"No cron entries configured")).

failures_render_test() ->
    B = render(shigoto_board_html:failures_html(stale())),
    ?assert(has(B, ~"Stale Jobs")),
    ?assert(has(B, ~"2026-07-04 09:00:00")).

page_shell_wraps_region_test() ->
    B = render(shigoto_board_html:page(~"queues", ~"/shigoto/sse/queues", ~"<p>x</p>")),
    ?assert(has(B, ~"<!DOCTYPE html>")),
    ?assert(has(B, ~"datastar.js")),
    ?assert(has(B, ~"data-init=\"@get('/shigoto/sse/queues')\"")),
    ?assert(has(B, ~"id=\"page\"")),
    %% active nav item marked
    ?assert(has(B, ~"class=\"active\"")).

static_page_has_no_stream_test() ->
    B = render(shigoto_board_html:page(~"cron", none, ~"<p>x</p>")),
    ?assertNot(has(B, ~"data-init")).

html_is_escaped_test() ->
    Evil = [
        #{
            worker => ~"<script>",
            total => 0,
            available => 0,
            executing => 0,
            completed => 0,
            retryable => 0,
            discarded => 0
        }
    ],
    B = render(shigoto_board_html:workers_html(Evil)),
    ?assert(has(B, ~"&lt;script&gt;")),
    ?assertNot(has(B, ~"<script>")).
