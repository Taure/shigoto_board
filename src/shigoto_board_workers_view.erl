-module(shigoto_board_workers_view).
-moduledoc """
Per-worker statistics view.
""".
-behaviour(arizona_view).

-export([mount/2, render/1, handle_info/2]).

-doc false.
mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(5000, self(), refresh);
        false -> ok
    end,
    {ok, #{
        layout => fun shigoto_board_layout:render/1,
        bindings => #{
            title => <<"Workers - Shigoto Board">>,
            active_page => <<"workers">>,
            worker_stats => get_worker_stats()
        }
    }}.

-doc false.
render(Bindings) ->
    Workers = maps:get(worker_stats, Bindings, []),
    iolist_to_binary([
        <<"<h2>Worker Statistics</h2>">>,
        <<"<table class=\"board-table\"><thead><tr>">>,
        <<"<th>Worker</th><th>Total</th><th>Available</th><th>Executing</th>">>,
        <<"<th>Completed</th><th>Retryable</th><th>Discarded</th>">>,
        <<"</tr></thead><tbody>">>,
        [worker_row(W) || W <- Workers],
        <<"</tbody></table>">>
    ]).

-doc false.
handle_info(refresh, View) ->
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(worker_stats, get_worker_stats(), State0),
    erlang:send_after(5000, self(), refresh),
    {[], arizona_view:update_state(State1, View)}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

get_worker_stats() ->
    case shigoto_dashboard:worker_stats() of
        {ok, Stats} -> Stats;
        _ -> []
    end.

worker_row(W) ->
    iolist_to_binary([
        <<"<tr>">>,
        <<"<td class=\"mono\">">>, maps:get(worker, W, <<"unknown">>), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(total, W, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(available, W, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(executing, W, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(completed, W, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(retryable, W, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(discarded, W, 0)), <<"</td>">>,
        <<"</tr>">>
    ]).

i2b(V) when is_integer(V) -> integer_to_binary(V);
i2b(_) -> <<"0">>.
