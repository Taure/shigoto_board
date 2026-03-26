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
    {ok, Stale} = shigoto_dashboard:stale_jobs(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{
        id => ~"overview_view",
        counts => Counts,
        queues => Queues,
        workers => Workers,
        stale_count => length(Stale)
    },
    Layout =
        {shigoto_board_layout, render, main_content, #{
            active_page => ~"overview",
            prefix => Prefix,
            ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
            arizona_prefix => arizona_nova:prefix()
        }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Counts = arizona_template:get_binding(counts, Bindings),
    Queues = arizona_template:get_binding(queues, Bindings),
    Workers = arizona_template:get_binding(workers, Bindings),
    StaleCount = arizona_template:get_binding(stale_count, Bindings),
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 2s</p>

        {stale_alert(StaleCount)}

        <div class="stat-grid">
            {stat_card(~"Available", ~"text-blue", maps:get(available, Counts, 0))}
            {stat_card(~"Executing", ~"text-amber", maps:get(executing, Counts, 0))}
            {stat_card(~"Retryable", ~"text-yellow", maps:get(retryable, Counts, 0))}
            {stat_card(~"Completed", ~"text-green", maps:get(completed, Counts, 0))}
            {stat_card(~"Discarded", ~"text-red", maps:get(discarded, Counts, 0))}
            {stat_card(~"Cancelled", ~"", maps:get(cancelled, Counts, 0))}
        </div>

        <div class="card">
            <div class="card-title">Queues</div>
            <table>
                <thead><tr>
                    <th>Queue</th>
                    <th class="text-right">Available</th>
                    <th class="text-right">Executing</th>
                    <th class="text-right">Retryable</th>
                </tr></thead>
                <tbody>
                    {arizona_template:render_list(fun render_queue_row/1, Queues)}
                </tbody>
            </table>
        </div>

        <div class="card">
            <div class="card-title">Workers</div>
            <table>
                <thead><tr>
                    <th>Worker</th>
                    <th class="text-right">Total</th>
                    <th class="text-right">Executing</th>
                    <th class="text-right">Completed</th>
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
    erlang:send_after(2000, self(), refresh),
    {ok, Counts} = shigoto_dashboard:job_counts(),
    {ok, Queues} = shigoto_dashboard:queue_stats(),
    {ok, Workers} = shigoto_dashboard:worker_stats(),
    {ok, Stale} = shigoto_dashboard:stale_jobs(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(counts, Counts, State),
    S2 = arizona_stateful:put_binding(queues, Queues, S1),
    S3 = arizona_stateful:put_binding(workers, Workers, S2),
    S4 = arizona_stateful:put_binding(stale_count, length(Stale), S3),
    {[], arizona_view:update_state(S4, View)}.

%%----------------------------------------------------------------------
%% Row renderers
%%----------------------------------------------------------------------

render_queue_row(Q) ->
    arizona_template:from_html(
        ~"""
    <tr>
        <td>{maps:get(queue, Q)}</td>
        <td class="text-right">{fmt(maps:get(available, Q, 0))}</td>
        <td class="text-right">{fmt(maps:get(executing, Q, 0))}</td>
        <td class="text-right">{fmt(maps:get(retryable, Q, 0))}</td>
    </tr>
    """
    ).

render_worker_row(W) ->
    arizona_template:from_html(
        ~"""
    <tr>
        <td class="mono">{maps:get(worker, W)}</td>
        <td class="text-right">{fmt(maps:get(total, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(executing, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(completed, W, 0))}</td>
        <td class="text-right">{fmt(maps:get(discarded, W, 0))}</td>
    </tr>
    """
    ).

%%----------------------------------------------------------------------
%% Helpers
%%----------------------------------------------------------------------

stale_alert(0) ->
    ~"";
stale_alert(Count) ->
    Msg = <<
        (integer_to_binary(Count))/binary, " stale job(s) detected - possible zombie processes"
    >>,
    arizona_template:from_html(
        ~"""
    <div class="alert alert-red">{Msg}</div>
    """
    ).

stat_card(Label, ColorClass, Value) ->
    arizona_template:from_html(
        ~"""
    <div class="stat">
        <div class="stat-label">{Label}</div>
        <div class="stat-value {ColorClass}">{fmt(Value)}</div>
    </div>
    """
    ).

fmt(N) when is_integer(N) -> integer_to_binary(N);
fmt(V) -> iolist_to_binary(io_lib:format(~"~p", [V])).
