-module(shigoto_board_jobs_view).
-moduledoc """
Job search and inspector view with retry/cancel actions.
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
            title => <<"Jobs - Shigoto Board">>,
            active_page => <<"jobs">>,
            jobs => get_jobs(#{}),
            filter_state => <<"all">>
        }
    }}.

-doc false.
render(Bindings) ->
    Jobs = maps:get(jobs, Bindings, []),
    FilterState = maps:get(filter_state, Bindings, <<"all">>),
    iolist_to_binary([
        <<"<h2>Jobs</h2>">>,
        <<"<div class=\"board-filters\">">>,
        filter_button(<<"all">>, <<"All">>, FilterState),
        filter_button(<<"available">>, <<"Available">>, FilterState),
        filter_button(<<"executing">>, <<"Executing">>, FilterState),
        filter_button(<<"retryable">>, <<"Retryable">>, FilterState),
        filter_button(<<"discarded">>, <<"Discarded">>, FilterState),
        filter_button(<<"cancelled">>, <<"Cancelled">>, FilterState),
        <<"</div>">>,
        <<"<table class=\"board-table\"><thead><tr>">>,
        <<"<th>ID</th><th>Worker</th><th>Queue</th><th>State</th>">>,
        <<"<th>Attempt</th><th>Priority</th><th>Progress</th><th>Actions</th>">>,
        <<"</tr></thead><tbody>">>,
        [job_row(J) || J <- Jobs],
        <<"</tbody></table>">>
    ]).

-doc false.
handle_event(<<"filter">>, #{<<"state">> := State}, View) ->
    Filters = case State of
        <<"all">> -> #{};
        S -> #{state => S}
    end,
    Jobs = get_jobs(Filters),
    State0 = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(jobs, Jobs, State0),
    State2 = arizona_stateful:put_binding(filter_state, State, State1),
    {[], arizona_view:update_state(State2, View)};
handle_event(<<"retry">>, #{<<"job_id">> := JobIdBin}, View) ->
    Pool = shigoto_config:pool(),
    JobId = binary_to_integer(JobIdBin),
    _ = shigoto:retry(Pool, JobId),
    {[], View};
handle_event(<<"cancel">>, #{<<"job_id">> := JobIdBin}, View) ->
    Pool = shigoto_config:pool(),
    JobId = binary_to_integer(JobIdBin),
    _ = shigoto:cancel(Pool, JobId),
    {[], View};
handle_event(_, _, View) ->
    {[], View}.

-doc false.
handle_info(refresh, View) ->
    State0 = arizona_view:get_state(View),
    FilterState = arizona_stateful:get_binding(filter_state, State0),
    Filters = case FilterState of
        <<"all">> -> #{};
        S -> #{state => S}
    end,
    State1 = arizona_stateful:put_binding(jobs, get_jobs(Filters), State0),
    erlang:send_after(5000, self(), refresh),
    {[], arizona_view:update_state(State1, View)}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

get_jobs(Filters) ->
    case shigoto_dashboard:search_jobs(Filters#{limit => 100}) of
        {ok, Jobs} -> Jobs;
        _ -> []
    end.

filter_button(State, Label, ActiveState) ->
    Class = case State of
        ActiveState -> <<"btn btn-active">>;
        _ -> <<"btn">>
    end,
    iolist_to_binary([
        <<"<button class=\"">>, Class,
        <<"\" arizona-click=\"filter\" arizona-value-state=\"">>, State, <<"\">">>,
        Label,
        <<"</button> ">>
    ]).

job_row(J) ->
    Id = maps:get(id, J, 0),
    IdBin = integer_to_binary(Id),
    State = maps:get(state, J, <<>>),
    iolist_to_binary([
        <<"<tr>">>,
        <<"<td>">>, IdBin, <<"</td>">>,
        <<"<td class=\"mono\">">>, to_bin(maps:get(worker, J, <<>>)), <<"</td>">>,
        <<"<td>">>, to_bin(maps:get(queue, J, <<>>)), <<"</td>">>,
        <<"<td><span class=\"state-badge state-">>, State, <<"\">">>, State, <<"</span></td>">>,
        <<"<td>">>, i2b(maps:get(attempt, J, 0)), <<"/">>, i2b(maps:get(max_attempts, J, 3)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(priority, J, 0)), <<"</td>">>,
        <<"<td>">>, i2b(maps:get(progress, J, 0)), <<"%</td>">>,
        <<"<td>">>,
        case State of
            <<"discarded">> ->
                <<"<button arizona-click=\"retry\" arizona-value-job_id=\"", IdBin/binary, "\">Retry</button>">>;
            <<"cancelled">> ->
                <<"<button arizona-click=\"retry\" arizona-value-job_id=\"", IdBin/binary, "\">Retry</button>">>;
            <<"available">> ->
                <<"<button arizona-click=\"cancel\" arizona-value-job_id=\"", IdBin/binary, "\">Cancel</button>">>;
            _ ->
                <<>>
        end,
        <<"</td>">>,
        <<"</tr>">>
    ]).

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_bin(_) -> <<>>.

i2b(V) when is_integer(V) -> integer_to_binary(V);
i2b(_) -> <<"0">>.
