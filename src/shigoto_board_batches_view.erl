-module(shigoto_board_batches_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    {ok, Batches} = shigoto_dashboard:batch_stats(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"batches_view", batches => Batches},
    Layout =
        {shigoto_board_layout, render, main_content, #{
            active_page => ~"batches",
            prefix => Prefix,
            ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
            arizona_prefix => arizona_nova:prefix()
        }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Batches = arizona_template:get_binding(batches, Bindings),
    case Batches of
        [] -> render_empty(Bindings);
        _ -> render_with_data(Bindings, Batches)
    end.

render_empty(Bindings) ->
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">Active Batches</div>
            <p class="empty">No active batches</p>
        </div>
    </div>
    """
    ).

render_with_data(Bindings, Batches) ->
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">Active Batches</div>
            <table>
                <thead><tr>
                    <th>ID</th>
                    <th>Callback</th>
                    <th>State</th>
                    <th>Progress</th>
                    <th class="text-right">Completed</th>
                    <th class="text-right">Discarded</th>
                    <th class="text-right">Total</th>
                </tr></thead>
                <tbody>
                    {arizona_template:render_list(fun render_batch_row/1, Batches)}
                </tbody>
            </table>
        </div>
    </div>
    """
    ).

handle_info(refresh, View) ->
    erlang:send_after(3000, self(), refresh),
    {ok, Batches} = shigoto_dashboard:batch_stats(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(batches, Batches, State),
    {[], arizona_view:update_state(S1, View)}.

%%----------------------------------------------------------------------
%% Row renderer
%%----------------------------------------------------------------------

render_batch_row(B) ->
    Total = maps:get(total_jobs, B, 0),
    Done = maps:get(completed_jobs, B, 0) + maps:get(discarded_jobs, B, 0),
    Pct =
        case Total of
            0 -> 0;
            _ -> (Done * 100) div Total
        end,
    arizona_template:from_html(
        ~"""
    <tr>
        <td class="mono">{integer_to_binary(maps:get(id, B))}</td>
        <td class="mono">{fmt_callback(maps:get(callback_worker, B, null))}</td>
        <td><span class="badge">{maps:get(state, B, ~"active")}</span></td>
        <td>
            <div class="bar">
                <div class="bar-fill bar-fill-green" style="width:{integer_to_binary(Pct)}%"></div>
            </div>
        </td>
        <td class="text-right">{integer_to_binary(maps:get(completed_jobs, B, 0))}</td>
        <td class="text-right">{integer_to_binary(maps:get(discarded_jobs, B, 0))}</td>
        <td class="text-right">{integer_to_binary(Total)}</td>
    </tr>
    """
    ).

%%----------------------------------------------------------------------
%% Helpers
%%----------------------------------------------------------------------

fmt_callback(null) -> ~"-";
fmt_callback(V) when is_binary(V) -> V;
fmt_callback(V) when is_atom(V) -> atom_to_binary(V);
fmt_callback(_) -> ~"-".
