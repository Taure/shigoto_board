-module(shigoto_board_failures_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    {ok, Stale} = shigoto_dashboard:stale_jobs(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"failures_view", stale_jobs => Stale},
    Layout =
        {shigoto_board_layout, render, main_content, #{
            active_page => ~"overview",
            prefix => Prefix,
            ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
            arizona_prefix => arizona_nova:prefix()
        }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Stale = arizona_template:get_binding(stale_jobs, Bindings),
    case Stale of
        [] -> render_empty(Bindings);
        _ -> render_with_data(Bindings, Stale)
    end.

render_empty(Bindings) ->
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">Stale Jobs</div>
            <p class="empty">No stale jobs detected</p>
        </div>
    </div>
    """
    ).

render_with_data(Bindings, Stale) ->
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="alert alert-red">
            {integer_to_binary(length(Stale))} stale job(s) detected - these may be zombie processes
        </div>
        <div class="card">
            <div class="card-title">
                Stale Jobs
                <span class="badge badge-red">{integer_to_binary(length(Stale))}</span>
            </div>
            <table>
                <thead><tr>
                    <th>ID</th>
                    <th>Worker</th>
                    <th>Queue</th>
                    <th class="text-right">Attempt</th>
                    <th>Last Heartbeat</th>
                </tr></thead>
                <tbody>
                    {arizona_template:render_list(fun render_stale_row/1, Stale)}
                </tbody>
            </table>
        </div>
    </div>
    """
    ).

handle_event(_Event, _Params, View) ->
    {[], View}.

handle_info(refresh, View) ->
    erlang:send_after(3000, self(), refresh),
    {ok, Stale} = shigoto_dashboard:stale_jobs(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(stale_jobs, Stale, State),
    {[], arizona_view:update_state(S1, View)}.

render_stale_row(J) ->
    IdBin = integer_to_binary(maps:get(id, J)),
    Heartbeat = fmt_timestamp(maps:get(heartbeat_at, J, null)),
    arizona_template:from_html(
        ~"""
    <tr>
        <td class="mono">{IdBin}</td>
        <td class="mono">{fmt_bin(maps:get(worker, J, ~"unknown"))}</td>
        <td>{fmt_bin(maps:get(queue, J, ~"default"))}</td>
        <td class="text-right">{integer_to_binary(maps:get(attempt, J, 0))}</td>
        <td class="text-red">{Heartbeat}</td>
    </tr>
    """
    ).

fmt_bin(V) when is_binary(V) -> V;
fmt_bin(V) when is_atom(V) -> atom_to_binary(V);
fmt_bin(_) -> ~"".

fmt_timestamp(null) ->
    ~"never";
fmt_timestamp(undefined) ->
    ~"never";
fmt_timestamp({{Y, Mo, D}, {H, Mi, S}}) ->
    iolist_to_binary(
        io_lib:format(~"~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", [Y, Mo, D, H, Mi, S])
    );
fmt_timestamp(V) when is_binary(V) ->
    V;
fmt_timestamp(_) ->
    ~"unknown".
