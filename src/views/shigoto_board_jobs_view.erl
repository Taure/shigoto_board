-module(shigoto_board_jobs_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    {ok, Jobs} = shigoto_dashboard:recent_failures(20),
    {ok, Stale} = shigoto_dashboard:stale_jobs(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"jobs_view", jobs => Jobs, stale => Stale},
    Layout = {shigoto_board_layout, render, main_content, #{
        active_page => ~"jobs", prefix => Prefix, ws_path => <<(arizona_nova:prefix())/binary, "/live">>, arizona_prefix => arizona_nova:prefix()
    }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Jobs = arizona_template:get_binding(jobs, Bindings),
    arizona_template:from_html(
        ~""""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">Recent Failures <span class="badge badge-red">{integer_to_binary(length(Jobs))}</span></div>
            <table>
                <thead><tr><th>ID</th><th>Worker</th><th>Queue</th><th>State</th><th>Attempt</th><th>Actions</th></tr></thead>
                <tbody>
                    {arizona_template:render_list(fun(Job) ->
                        IdBin = integer_to_binary(maps:get(id, Job)),
                        RetryClick = <<"arizona.pushEventTo('jobs_view', 'retry', {job_id: '", IdBin/binary, "'})">>,
                        CancelClick = <<"arizona.pushEventTo('jobs_view', 'cancel', {job_id: '", IdBin/binary, "'})">>,
                        arizona_template:from_html(~"""
                        <tr>
                            <td class="mono">{IdBin}</td>
                            <td class="mono">{maps:get(worker, Job, ~"unknown")}</td>
                            <td>{maps:get(queue, Job, ~"default")}</td>
                            <td><span class="badge {state_badge(maps:get(state, Job, ~"unknown"))}">{maps:get(state, Job, ~"unknown")}</span></td>
                            <td class="text-right">{integer_to_binary(maps:get(attempt, Job, 0))}</td>
                            <td>
                                <button class="btn btn-sm btn-green" onclick="{RetryClick}">Retry</button>
                                <button class="btn btn-sm btn-red" onclick="{CancelClick}">Cancel</button>
                            </td>
                        </tr>
                        """)
                    end, Jobs)}
                </tbody>
            </table>
        </div>
    </div>
    """"
    ).

handle_event(~"retry", #{~"job_id" := JobIdBin}, View) ->
    logger:notice(#{msg => ~"Retrying job", job_id => JobIdBin}),
    JobId = binary_to_integer(JobIdBin),
    Pool = shigoto_config:pool(),
    shigoto:retry(Pool, JobId),
    refresh_data(View);
handle_event(~"cancel", #{~"job_id" := JobIdBin}, View) ->
    logger:notice(#{msg => ~"Cancelling job", job_id => JobIdBin}),
    JobId = binary_to_integer(JobIdBin),
    Pool = shigoto_config:pool(),
    shigoto:cancel(Pool, JobId),
    refresh_data(View);
handle_event(Event, Params, View) ->
    logger:warning(#{msg => ~"Unhandled jobs event", event => Event, params => Params}),
    {[], View}.

handle_info(refresh, View) ->
    erlang:send_after(3000, self(), refresh),
    refresh_data(View).

refresh_data(View) ->
    {ok, Jobs} = shigoto_dashboard:recent_failures(20),
    {ok, Stale} = shigoto_dashboard:stale_jobs(),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(jobs, Jobs, State),
    S2 = arizona_stateful:put_binding(stale, Stale, S1),
    {[], arizona_view:update_state(S2, View)}.

state_badge(~"completed") -> ~"badge-green";
state_badge(~"executing") -> ~"badge-blue";
state_badge(~"available") -> ~"badge-blue";
state_badge(~"retryable") -> ~"badge-yellow";
state_badge(~"discarded") -> ~"badge-red";
state_badge(~"cancelled") -> ~"badge-gray";
state_badge(_) -> ~"".
