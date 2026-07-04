-module(shigoto_board_page_controller_tests).
-include_lib("eunit/include/eunit.hrl").

-define(M, shigoto_board_page_controller).

%% ---------------------------------------------------------------------------
%% pure helpers
%% ---------------------------------------------------------------------------

filters_from_qs_defaults_test() ->
    F = ?M:filters_from_qs([]),
    ?assertEqual(~"", maps:get(filter_state, F)),
    ?assertEqual(~"", maps:get(filter_queue, F)),
    ?assertEqual(~"", maps:get(filter_worker, F)),
    ?assertEqual(1, maps:get(page, F)).

filters_from_qs_parses_test() ->
    F = ?M:filters_from_qs([{~"state", ~"retryable"}, {~"queue", ~"mailers"}, {~"page", ~"3"}]),
    ?assertEqual(~"retryable", maps:get(filter_state, F)),
    ?assertEqual(~"mailers", maps:get(filter_queue, F)),
    ?assertEqual(3, maps:get(page, F)).

filters_from_qs_bad_page_defaults_to_one_test() ->
    ?assertEqual(1, maps:get(page, ?M:filters_from_qs([{~"page", ~"nope"}]))),
    ?assertEqual(1, maps:get(page, ?M:filters_from_qs([{~"page", ~"0"}]))).

page_atom_maps_known_pages_test() ->
    ?assertEqual(overview, ?M:page_atom(~"overview")),
    ?assertEqual(queues, ?M:page_atom(~"queues")),
    ?assertEqual(jobs, ?M:page_atom(~"jobs")),
    ?assertEqual(failures, ?M:page_atom(~"failures")).

page_atom_unknown_defaults_overview_test() ->
    ?assertEqual(overview, ?M:page_atom(~"bogus")).

%% ---------------------------------------------------------------------------
%% full controller path (dashboard mocked)
%% ---------------------------------------------------------------------------

controller_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        fun index_returns_full_page/0,
        fun jobs_uses_qs_filters/0,
        fun page_inner_survives_dashboard_error/0
    ]}.

setup() ->
    application:set_env(shigoto_board, prefix, ~"/shigoto"),
    meck:new(shigoto_dashboard, [non_strict]),
    meck:expect(shigoto_dashboard, job_counts, 0, {ok, #{available => 3}}),
    meck:expect(shigoto_dashboard, queue_stats, 0, {ok, [#{queue => ~"default", available => 3}]}),
    meck:expect(shigoto_dashboard, worker_stats, 0, {ok, []}),
    meck:expect(shigoto_dashboard, stale_jobs, 0, {ok, []}),
    meck:expect(shigoto_dashboard, batch_stats, 0, {ok, []}),
    meck:expect(shigoto_dashboard, search_jobs, fun(F) ->
        {ok, [
            #{
                id => 1,
                state => ~"available",
                worker => ~"w",
                queue => ~"default",
                attempt => 0,
                max_attempts => 3,
                inserted_at => undefined,
                filters => F
            }
        ]}
    end),
    ok.

cleanup(_) ->
    meck:unload(shigoto_dashboard),
    application:unset_env(shigoto_board, prefix).

index_returns_full_page() ->
    {status, 200, Headers, Body} = ?M:index(#{}),
    ?assertMatch(#{~"content-security-policy" := _}, Headers),
    ?assert(is_binary(Body)),
    ?assert(binary:match(Body, ~"<!DOCTYPE html>") =/= nomatch),
    ?assert(binary:match(Body, ~"/shigoto/sse/overview") =/= nomatch).

jobs_uses_qs_filters() ->
    {status, 200, _H, Body} = ?M:jobs(#{qs => ~"state=available&page=2"}),
    %% stream path carries the filters + page
    ?assert(binary:match(Body, ~"/sse/jobs?state=available&page=2") =/= nomatch),
    %% search was called with the parsed filter + correct offset
    History = meck:history(shigoto_dashboard),
    ?assert(
        lists:any(
            fun
                ({_, {_, search_jobs, [F]}, _}) when is_map(F) ->
                    maps:get(state, F, undefined) =:= ~"available" andalso
                        maps:get(offset, F, undefined) =:= 25;
                (_) ->
                    false
            end,
            History
        )
    ).

page_inner_survives_dashboard_error() ->
    meck:expect(shigoto_dashboard, queue_stats, 0, {error, no_connection}),
    Inner = iolist_to_binary(?M:page_inner(queues, undefined)),
    ?assert(binary:match(Inner, ~"Queues") =/= nomatch).
