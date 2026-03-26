-module(shigoto_board_workers_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    {ok, Workers} = shigoto_dashboard:worker_stats(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"workers_view", workers => Workers},
    Layout =
        {shigoto_board_layout, render, main_content, #{
            active_page => ~"workers",
            prefix => Prefix,
            ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
            arizona_prefix => arizona_nova:prefix()
        }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Workers = arizona_template:get_binding(workers, Bindings),
    case Workers of
        [] -> render_empty(Bindings);
        _ -> render_with_data(Bindings, Workers)
    end.

render_empty(Bindings) ->
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">Workers</div>
            <p class="empty">No worker data available</p>
        </div>
    </div>
    """
    ).

render_with_data(Bindings, Workers) ->
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">
                Workers
                <span class="badge badge-blue">{integer_to_binary(length(Workers))}</span>
            </div>
            <table>
                <thead><tr>
                    <th>Worker</th>
                    <th class="text-right">Total</th>
                    <th class="text-right">Available</th>
                    <th class="text-right">Executing</th>
                    <th class="text-right">Completed</th>
                    <th class="text-right">Retryable</th>
                    <th class="text-right">Discarded</th>
                </tr></thead>
                <tbody>
                    {arizona_template:render_list(fun render_worker_row/1, Workers)}
                </tbody>
            </table>
        </div>
    </div>
    """
    ).

handle_info(refresh, View) ->
    erlang:send_after(3000, self(), refresh),
    {ok, Workers} = shigoto_dashboard:worker_stats(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(workers, Workers, State),
    {[], arizona_view:update_state(S1, View)}.

render_worker_row(W) ->
    arizona_template:from_html(
        ~"""
    <tr>
        <td class="mono">{maps:get(worker, W, ~"unknown")}</td>
        <td class="text-right">{fmt(maps:get(total, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(available, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(executing, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(completed, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(retryable, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(discarded, W, 0))}</td>
    </tr>
    """
    ).

fmt(N) when is_integer(N) -> integer_to_binary(N);
fmt(V) -> iolist_to_binary(io_lib:format(~"~p", [V])).
