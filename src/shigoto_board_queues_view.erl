-module(shigoto_board_queues_view).
-moduledoc """
Queue detail view with per-queue statistics and pause/resume controls.
""".
-behaviour(arizona_view).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

-doc false.
mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    {ok, #{
        layout => fun shigoto_board_layout:render/1,
        bindings => #{
            title => <<"Queues - Shigoto Board">>,
            active_page => <<"queues">>,
            queue_stats => get_queue_stats()
        }
    }}.

-doc false.
render(Bindings) ->
    QueueStats = maps:get(queue_stats, Bindings, []),
    iolist_to_binary([
        <<"<h2>Queue Details</h2>">>,
        <<"<table class=\"board-table\"><thead><tr>">>,
        <<"<th>Queue</th><th>Available</th><th>Executing</th><th>Retryable</th>">>,
        <<"<th>Completed</th><th>Discarded</th><th>Actions</th>">>,
        <<"</tr></thead><tbody>">>,
        [queue_row(Q) || Q <- QueueStats],
        <<"</tbody></table>">>
    ]).

-doc false.
handle_event(<<"pause">>, #{<<"queue">> := Queue}, View) ->
    _ = shigoto:pause_queue(Queue),
    {[], View};
handle_event(<<"resume">>, #{<<"queue">> := Queue}, View) ->
    _ = shigoto:resume_queue(Queue),
    {[], View};
handle_event(_, _, View) ->
    {[], View}.

-doc false.
handle_info(refresh, View) ->
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(queue_stats, get_queue_stats(), State0),
    erlang:send_after(3000, self(), refresh),
    {[], arizona_view:update_state(State1, View)}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

get_queue_stats() ->
    case shigoto_dashboard:queue_stats() of
        {ok, Stats} -> Stats;
        _ -> []
    end.

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
        <<"<td>">>,
        <<"<button arizona-click=\"pause\" arizona-value-queue=\"">>, Queue, <<"\">Pause</button> ">>,
        <<"<button arizona-click=\"resume\" arizona-value-queue=\"">>, Queue, <<"\">Resume</button>">>,
        <<"</td>">>,
        <<"</tr>">>
    ]).

i2b(V) when is_integer(V) -> integer_to_binary(V);
i2b(_) -> <<"0">>.
