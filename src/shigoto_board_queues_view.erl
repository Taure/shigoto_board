-module(shigoto_board_queues_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(2000, self(), refresh);
        false -> ok
    end,
    {ok, Queues} = shigoto_dashboard:queue_stats(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"queues_view", queues => Queues, paused => #{}},
    Layout = {shigoto_board_layout, render, main_content, #{
        active_page => ~"queues",
        prefix => Prefix,
        ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
        arizona_prefix => arizona_nova:prefix()
    }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Queues = arizona_template:get_binding(queues, Bindings),
    Paused = arizona_template:get_binding(paused, Bindings),
    EnrichedQueues = [Q#{is_paused => maps:get(maps:get(queue, Q), Paused, false)} || Q <- Queues],
    arizona_template:from_html(~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 2s</p>
        <div class="card">
            <div class="card-title">Queues</div>
            <table>
                <thead><tr>
                    <th>Queue</th>
                    <th>Status</th>
                    <th class="text-right">Available</th>
                    <th class="text-right">Executing</th>
                    <th class="text-right">Retryable</th>
                    <th>Actions</th>
                </tr></thead>
                <tbody>
                    {arizona_template:render_list(fun render_queue_row/1, EnrichedQueues)}
                </tbody>
            </table>
        </div>
    </div>
    """).

handle_event(~"pause_queue", #{~"queue" := Queue}, View) ->
    logger:notice(#{msg => ~"Pausing queue", queue => Queue}),
    shigoto:pause_queue(Queue),
    update_pause_state(Queue, true, View);
handle_event(~"resume_queue", #{~"queue" := Queue}, View) ->
    logger:notice(#{msg => ~"Resuming queue", queue => Queue}),
    shigoto:resume_queue(Queue),
    update_pause_state(Queue, false, View);
handle_event(_Event, _Params, View) ->
    {[], View}.

handle_info(refresh, View) ->
    erlang:send_after(2000, self(), refresh),
    {ok, Queues} = shigoto_dashboard:queue_stats(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(queues, Queues, State),
    {[], arizona_view:update_state(S1, View)}.

%%----------------------------------------------------------------------
%% Row renderer
%%----------------------------------------------------------------------

render_queue_row(Q) ->
    QName = maps:get(queue, Q),
    IsPaused = maps:get(is_paused, Q, false),
    StatusBadge = case IsPaused of
        true -> ~"<span class=\"badge badge-yellow\">paused</span>";
        false -> ~"<span class=\"badge badge-green\">active</span>"
    end,
    PauseClick = <<"arizona.pushEventTo('queues_view', 'pause_queue', {queue: '", QName/binary, "'})">>,
    ResumeClick = <<"arizona.pushEventTo('queues_view', 'resume_queue', {queue: '", QName/binary, "'})">>,
    arizona_template:from_html(~"""
    <tr>
        <td>{QName}</td>
        <td>{StatusBadge}</td>
        <td class="text-right">{fmt(maps:get(available, Q, 0))}</td>
        <td class="text-right">{fmt(maps:get(executing, Q, 0))}</td>
        <td class="text-right">{fmt(maps:get(retryable, Q, 0))}</td>
        <td>
            <button class="btn btn-sm btn-red" onclick="{PauseClick}">Pause</button>
            <button class="btn btn-sm btn-green" onclick="{ResumeClick}">Resume</button>
        </td>
    </tr>
    """).

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

update_pause_state(Queue, IsPaused, View) ->
    State = arizona_view:get_state(View),
    Paused = arizona_stateful:get_binding(paused, State),
    NewPaused = case IsPaused of
        true -> Paused#{Queue => true};
        false -> maps:remove(Queue, Paused)
    end,
    {ok, Queues} = shigoto_dashboard:queue_stats(),
    S1 = arizona_stateful:put_binding(paused, NewPaused, State),
    S2 = arizona_stateful:put_binding(queues, Queues, S1),
    {[], arizona_view:update_state(S2, View)}.

fmt(N) when is_integer(N) -> integer_to_binary(N);
fmt(V) -> iolist_to_binary(io_lib:format(~"~p", [V])).
