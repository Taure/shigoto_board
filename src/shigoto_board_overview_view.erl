-module(shigoto_board_overview_view).
-moduledoc """
Overview dashboard showing global job counts, queue health, and recent activity.
""".
-behaviour(arizona_view).

-export([mount/2, render/1, handle_info/2]).

-doc false.
mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    Counts = get_counts(),
    QueueStats = get_queue_stats(),
    Stale = get_stale_count(),
    {ok, #{
        layout => fun shigoto_board_layout:render/1,
        bindings => #{
            title => <<"Overview - Shigoto Board">>,
            active_page => <<"overview">>,
            counts => Counts,
            queue_stats => QueueStats,
            stale_count => Stale
        }
    }}.

-doc false.
render(Bindings) ->
    Counts = maps:get(counts, Bindings, #{}),
    QueueStats = maps:get(queue_stats, Bindings, []),
    Stale = maps:get(stale_count, Bindings, 0),
    iolist_to_binary([
        <<"<div class=\"board-grid\">">>,
        stat_card(<<"Available">>, maps:get(available, Counts, 0), <<"stat-available">>),
        stat_card(<<"Executing">>, maps:get(executing, Counts, 0), <<"stat-executing">>),
        stat_card(<<"Retryable">>, maps:get(retryable, Counts, 0), <<"stat-retryable">>),
        stat_card(<<"Completed">>, maps:get(completed, Counts, 0), <<"stat-completed">>),
        stat_card(<<"Discarded">>, maps:get(discarded, Counts, 0), <<"stat-discarded">>),
        stat_card(<<"Stale">>, Stale, <<"stat-stale">>),
        <<"</div>">>,
        <<"<h2>Queues</h2>">>,
        <<"<table class=\"board-table\"><thead><tr>">>,
        <<"<th>Queue</th><th>Available</th><th>Executing</th><th>Retryable</th><th>Completed</th><th>Discarded</th>">>,
        <<"</tr></thead><tbody>">>,
        [queue_row(Q) || Q <- QueueStats],
        <<"</tbody></table>">>
    ]).

-doc false.
handle_info(refresh, View) ->
    Counts = get_counts(),
    QueueStats = get_queue_stats(),
    Stale = get_stale_count(),
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(counts, Counts, State0),
    State2 = arizona_stateful:put_binding(queue_stats, QueueStats, State1),
    State3 = arizona_stateful:put_binding(stale_count, Stale, State2),
    erlang:send_after(3000, self(), refresh),
    {[], arizona_view:update_state(State3, View)}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

get_counts() ->
    case shigoto_dashboard:job_counts() of
        {ok, Counts} -> Counts;
        _ -> #{}
    end.

get_queue_stats() ->
    case shigoto_dashboard:queue_stats() of
        {ok, Stats} -> Stats;
        _ -> []
    end.

get_stale_count() ->
    case shigoto_dashboard:stale_jobs() of
        {ok, Jobs} -> length(Jobs);
        _ -> 0
    end.

stat_card(Label, Value, Class) ->
    ValBin = integer_to_binary(Value),
    iolist_to_binary([
        <<"<div class=\"stat-card ">>, Class, <<"\">">>,
        <<"<div class=\"stat-value\">">>, ValBin, <<"</div>">>,
        <<"<div class=\"stat-label\">">>, Label, <<"</div>">>,
        <<"</div>">>
    ]).

queue_row(QueueMap) ->
    Queue = maps:get(queue, QueueMap, <<"unknown">>),
    iolist_to_binary([
        <<"<tr>">>,
        <<"<td>">>, Queue, <<"</td>">>,
        <<"<td>">>, i2b(maps:get(available, QueueMap, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(executing, QueueMap, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(retryable, QueueMap, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(completed, QueueMap, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(discarded, QueueMap, 0)), <<"</td>">>,
        <<"</tr>">>
    ]).

i2b(V) when is_integer(V) -> integer_to_binary(V);
i2b(_) -> <<"0">>.
