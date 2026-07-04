-module(shigoto_board_action_controller_tests).
-include_lib("eunit/include/eunit.hrl").

-define(M, shigoto_board_action_controller).

action_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        fun pause_calls_shigoto_and_patches/0,
        fun resume_calls_shigoto/0,
        fun retry_calls_shigoto_with_pool/0,
        fun cancel_calls_shigoto/0,
        fun bad_job_id_is_rejected/0
    ]}.

setup() ->
    application:set_env(shigoto_board, prefix, ~"/shigoto"),
    meck:new(shigoto, [non_strict]),
    meck:expect(shigoto, pause_queue, 1, ok),
    meck:expect(shigoto, resume_queue, 1, ok),
    meck:expect(shigoto, retry, 2, ok),
    meck:expect(shigoto, cancel, 2, ok),
    meck:new(shigoto_config, [non_strict]),
    meck:expect(shigoto_config, pool, 0, my_pool),
    meck:new(shigoto_dashboard, [non_strict]),
    meck:expect(shigoto_dashboard, queue_stats, 0, {ok, []}),
    meck:expect(shigoto_dashboard, search_jobs, 1, {ok, []}),
    ok.

cleanup(_) ->
    meck:unload([shigoto, shigoto_config, shigoto_dashboard]),
    application:unset_env(shigoto_board, prefix).

req(Bindings, Qs) ->
    #{bindings => Bindings, qs => Qs}.

pause_calls_shigoto_and_patches() ->
    {status, 200, Headers, Body} = ?M:pause_queue(req(#{~"queue" => ~"default"}, ~"")),
    ?assertEqual(~"default", meck:capture(first, shigoto, pause_queue, ['_'], 1)),
    ?assertMatch(#{~"content-type" := _}, Headers),
    ?assert(is_binary(Body)).

resume_calls_shigoto() ->
    {status, 200, _, _} = ?M:resume_queue(req(#{~"queue" => ~"mailers"}, ~"")),
    ?assertEqual(~"mailers", meck:capture(first, shigoto, resume_queue, ['_'], 1)).

retry_calls_shigoto_with_pool() ->
    {status, 200, _, _} = ?M:retry(req(#{~"id" => ~"42"}, ~"state=retryable&page=1")),
    ?assertEqual(my_pool, meck:capture(first, shigoto, retry, ['_', '_'], 1)),
    ?assertEqual(42, meck:capture(first, shigoto, retry, ['_', '_'], 2)).

cancel_calls_shigoto() ->
    {status, 200, _, _} = ?M:cancel(req(#{~"id" => ~"7"}, ~"")),
    ?assertEqual(my_pool, meck:capture(first, shigoto, cancel, ['_', '_'], 1)),
    ?assertEqual(7, meck:capture(first, shigoto, cancel, ['_', '_'], 2)).

bad_job_id_is_rejected() ->
    ?assertEqual({status, 400}, ?M:retry(req(#{~"id" => ~"notanint"}, ~""))),
    ?assertEqual(0, meck:num_calls(shigoto, retry, ['_', '_'])).
