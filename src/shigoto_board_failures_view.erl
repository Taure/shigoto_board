-module(shigoto_board_failures_view).
-moduledoc """
Recent failures view with error details and retry actions.
""".
-behaviour(arizona_view).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

-doc false.
mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(5000, self(), refresh);
        false -> ok
    end,
    {ok, #{
        layout => fun shigoto_board_layout:render/1,
        bindings => #{
            title => <<"Failures - Shigoto Board">>,
            active_page => <<"failures">>,
            failures => get_failures()
        }
    }}.

-doc false.
render(Bindings) ->
    Failures = maps:get(failures, Bindings, []),
    iolist_to_binary([
        <<"<h2>Recent Failures</h2>">>,
        <<"<table class=\"board-table\"><thead><tr>">>,
        <<"<th>ID</th><th>Worker</th><th>Queue</th><th>State</th>">>,
        <<"<th>Attempt</th><th>Last Error</th><th>Actions</th>">>,
        <<"</tr></thead><tbody>">>,
        [failure_row(F) || F <- Failures],
        <<"</tbody></table>">>
    ]).

-doc false.
handle_event(<<"retry">>, #{<<"job_id">> := JobIdBin}, View) ->
    Pool = shigoto_config:pool(),
    JobId = binary_to_integer(JobIdBin),
    _ = shigoto:retry(Pool, JobId),
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(failures, get_failures(), State0),
    {[], arizona_view:update_state(State1, View)};
handle_event(_, _, View) ->
    {[], View}.

-doc false.
handle_info(refresh, View) ->
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(failures, get_failures(), State0),
    erlang:send_after(5000, self(), refresh),
    {[], arizona_view:update_state(State1, View)}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

get_failures() ->
    case shigoto_dashboard:recent_failures(50) of
        {ok, Failures} -> Failures;
        _ -> []
    end.

failure_row(F) ->
    Id = maps:get(id, F, 0),
    IdBin = integer_to_binary(Id),
    State = maps:get(state, F, <<>>),
    LastError = extract_last_error(maps:get(errors, F, <<"[]">>)),
    iolist_to_binary([
        <<"<tr>">>,
        <<"<td>">>,
        IdBin,
        <<"</td>">>,
        <<"<td class=\"mono\">">>,
        to_bin(maps:get(worker, F, <<>>)),
        <<"</td>">>,
        <<"<td>">>,
        to_bin(maps:get(queue, F, <<>>)),
        <<"</td>">>,
        <<"<td><span class=\"state-badge state-">>,
        State,
        <<"\">">>,
        State,
        <<"</span></td>">>,
        <<"<td>">>,
        i2b(maps:get(attempt, F, 0)),
        <<"/">>,
        i2b(maps:get(max_attempts, F, 3)),
        <<"</td>">>,
        <<"<td class=\"mono error-text\">">>,
        truncate(LastError, 80),
        <<"</td>">>,
        <<"<td>">>,
        case State of
            <<"discarded">> ->
                <<"<button arizona-click=\"retry\" arizona-value-job_id=\"", IdBin/binary,
                    "\">Retry</button>">>;
            _ ->
                <<>>
        end,
        <<"</td>">>,
        <<"</tr>">>
    ]).

extract_last_error(Errors) when is_binary(Errors) ->
    try
        case json:decode(Errors) of
            List when is_list(List), length(List) > 0 ->
                Last = lists:last(List),
                maps:get(<<"error">>, Last, <<>>);
            _ ->
                <<>>
        end
    catch
        _:_ -> <<>>
    end;
extract_last_error(Errors) when is_list(Errors), length(Errors) > 0 ->
    Last = lists:last(Errors),
    maps:get(<<"error">>, Last, <<>>);
extract_last_error(_) ->
    <<>>.

truncate(Bin, Max) when byte_size(Bin) > Max ->
    <<(binary:part(Bin, 0, Max))/binary, "...">>;
truncate(Bin, _Max) ->
    Bin.

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_bin(_) -> <<>>.

i2b(V) when is_integer(V) -> integer_to_binary(V);
i2b(_) -> <<"0">>.
