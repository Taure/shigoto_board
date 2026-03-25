-module(shigoto_board_overview_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(2000, self(), refresh);
        false -> ok
    end,
    {ok, Counts} = shigoto_dashboard:job_counts(),
    {ok, Queues} = shigoto_dashboard:queue_stats(),
    {ok, Workers} = shigoto_dashboard:worker_stats(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{
        id => ~"overview_view",
        counts => Counts,
        queues => Queues,
        workers => Workers
    },
    Layout =
        {shigoto_board_layout, render, main_content, #{
            active_page => ~"overview",
            prefix => Prefix,
            ws_path => <<(arizona_nova:prefix())/binary, "/live">>, arizona_prefix => arizona_nova:prefix()
        }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Counts = arizona_template:get_binding(counts, Bindings),
    Queues = arizona_template:get_binding(queues, Bindings),
    Workers = arizona_template:get_binding(workers, Bindings),
    arizona_template:from_html(
        ~""""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 2s</p>
        <div class="stat-grid">
            <div class="stat"><div class="stat-label">Available</div><div class="stat-value text-blue">{fmt(maps:get(available, Counts, 0))}</div></div>
            <div class="stat"><div class="stat-label">Executing</div><div class="stat-value text-amber">{fmt(maps:get(executing, Counts, 0))}</div></div>
            <div class="stat"><div class="stat-label">Retryable</div><div class="stat-value text-yellow">{fmt(maps:get(retryable, Counts, 0))}</div></div>
            <div class="stat"><div class="stat-label">Completed</div><div class="stat-value text-green">{fmt(maps:get(completed, Counts, 0))}</div></div>
            <div class="stat"><div class="stat-label">Discarded</div><div class="stat-value text-red">{fmt(maps:get(discarded, Counts, 0))}</div></div>
            <div class="stat"><div class="stat-label">Cancelled</div><div class="stat-value">{fmt(maps:get(cancelled, Counts, 0))}</div></div>
        </div>
        <div class="card">
            <div class="card-title">Queues</div>
            <table>
                <thead><tr><th>Queue</th><th class="text-right">Available</th><th class="text-right">Executing</th><th class="text-right">Retryable</th></tr></thead>
                <tbody>
                    {arizona_template:render_list(fun(Q) ->
                        arizona_template:from_html(~"""
                        <tr>
                            <td>{maps:get(queue, Q)}</td>
                            <td class="text-right">{fmt(maps:get(available, Q, 0))}</td>
                            <td class="text-right">{fmt(maps:get(executing, Q, 0))}</td>
                            <td class="text-right">{fmt(maps:get(retryable, Q, 0))}</td>
                        </tr>
                        """)
                    end, Queues)}
                </tbody>
            </table>
        </div>
        <div class="card">
            <div class="card-title">Workers</div>
            <table>
                <thead><tr><th>Worker</th><th class="text-right">Total</th><th class="text-right">Executing</th><th class="text-right">Completed</th></tr></thead>
                <tbody>
                    {arizona_template:render_list(fun(W) ->
                        arizona_template:from_html(~"""
                        <tr>
                            <td class="mono">{maps:get(worker, W)}</td>
                            <td class="text-right">{fmt(maps:get(total, W, 0))}</td>
                            <td class="text-right">{fmt(maps:get(executing, W, 0))}</td>
                            <td class="text-right">{fmt(maps:get(completed, W, 0))}</td>
                        </tr>
                        """)
                    end, Workers)}
                </tbody>
            </table>
        </div>
    </div>
    """"
    ).

handle_info(refresh, View) ->
    erlang:send_after(2000, self(), refresh),
    {ok, Counts} = shigoto_dashboard:job_counts(),
    {ok, Queues} = shigoto_dashboard:queue_stats(),
    {ok, Workers} = shigoto_dashboard:worker_stats(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(counts, Counts, State),
    S2 = arizona_stateful:put_binding(queues, Queues, S1),
    S3 = arizona_stateful:put_binding(workers, Workers, S2),
    {[], arizona_view:update_state(S3, View)}.

fmt(N) when is_integer(N) -> integer_to_binary(N);
fmt(V) -> iolist_to_binary(io_lib:format(~"~p", [V])).
