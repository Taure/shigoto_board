-module(shigoto_board_batches_view).
-moduledoc """
Active batches view.
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
            title => <<"Batches - Shigoto Board">>,
            active_page => <<"batches">>,
            batches => get_batches()
        }
    }}.

-doc false.
render(Bindings) ->
    Batches = maps:get(batches, Bindings, []),
    iolist_to_binary([
        <<"<h2>Active Batches</h2>">>,
        <<"<table class=\"board-table\"><thead><tr>">>,
        <<"<th>ID</th><th>Callback</th><th>State</th>">>,
        <<"<th>Total</th><th>Completed</th><th>Discarded</th><th>Progress</th>">>,
        <<"</tr></thead><tbody>">>,
        [batch_row(B) || B <- Batches],
        <<"</tbody></table>">>
    ]).

-doc false.
handle_info(refresh, View) ->
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(batches, get_batches(), State0),
    erlang:send_after(5000, self(), refresh),
    {[], arizona_view:update_state(State1, View)}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

get_batches() ->
    case shigoto_dashboard:batch_stats() of
        {ok, Batches} -> Batches;
        _ -> []
    end.

batch_row(B) ->
    Id = maps:get(id, B, 0),
    Total = maps:get(total_jobs, B, 0),
    Completed = maps:get(completed_jobs, B, 0),
    Discarded = maps:get(discarded_jobs, B, 0),
    Pct = case Total of
        0 -> 0;
        _ -> ((Completed + Discarded) * 100) div Total
    end,
    iolist_to_binary([
        <<"<tr>">>,
        <<"<td>">>, integer_to_binary(Id), <<"</td>">>,
        <<"<td class=\"mono\">">>, to_bin(maps:get(callback_worker, B, null)), <<"</td>">>,
        <<"<td>">>, to_bin(maps:get(state, B, <<>>)), <<"</td>">>,
        <<"<td>">>, integer_to_binary(Total), <<"</td>">>,
        <<"<td>">>, integer_to_binary(Completed), <<"</td>">>,
        <<"<td>">>, integer_to_binary(Discarded), <<"</td>">>,
        <<"<td>">>, integer_to_binary(Pct), <<"%</td>">>,
        <<"</tr>">>
    ]).

to_bin(null) -> <<"-">>;
to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_bin(_) -> <<>>.
