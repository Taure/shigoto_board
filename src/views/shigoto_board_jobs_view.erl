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
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"jobs_view", jobs => Jobs},
    Layout = {shigoto_board_layout, render, main_content, #{
        active_page => ~"jobs",
        prefix => Prefix,
        ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
        arizona_prefix => arizona_nova:prefix()
    }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Jobs = arizona_template:get_binding(jobs, Bindings),
    arizona_template:from_html(~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>
        <div class="card">
            <div class="card-title">
                Recent Failures
                <span class="badge badge-red">{integer_to_binary(length(Jobs))}</span>
            </div>
            <table>
                <thead><tr>
                    <th>ID</th>
                    <th>Worker</th>
                    <th>Queue</th>
                    <th>State</th>
                    <th class="text-right">Attempt</th>
                    <th>Actions</th>
                </tr></thead>
                <tbody>
                    {arizona_template:render_list(fun render_job_row/1, Jobs)}
                </tbody>
            </table>
        </div>
    </div>
    """).

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
handle_event(_Event, _Params, View) ->
    {[], View}.

handle_info(refresh, View) ->
    erlang:send_after(3000, self(), refresh),
    refresh_data(View).

%%----------------------------------------------------------------------
%% Row renderer
%%----------------------------------------------------------------------

render_job_row(Job) ->
    IdBin = integer_to_binary(maps:get(id, Job)),
    Worker = maps:get(worker, Job, ~"unknown"),
    Queue = maps:get(queue, Job, ~"default"),
    JobState = maps:get(state, Job, ~"unknown"),
    Attempt = integer_to_binary(maps:get(attempt, Job, 0)),
    RetryClick = <<"arizona.pushEventTo('jobs_view', 'retry', {job_id: '", IdBin/binary, "'})">>,
    CancelClick = <<"arizona.pushEventTo('jobs_view', 'cancel', {job_id: '", IdBin/binary, "'})">>,
    arizona_template:from_html(~"""
    <tr>
        <td class="mono">{IdBin}</td>
        <td class="mono">{Worker}</td>
        <td>{Queue}</td>
        <td><span class="badge {state_badge(JobState)}">{JobState}</span></td>
        <td class="text-right">{Attempt}</td>
        <td>
            <button class="btn btn-sm btn-green" onclick="{RetryClick}">Retry</button>
            <button class="btn btn-sm btn-red" onclick="{CancelClick}">Cancel</button>
        </td>
    </tr>
    """).

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

refresh_data(View) ->
    {ok, Jobs} = shigoto_dashboard:recent_failures(20),
    State = arizona_view:get_state(View),
    S1 = arizona_stateful:put_binding(jobs, Jobs, State),
    {[], arizona_view:update_state(S1, View)}.

state_badge(~"completed") -> ~"badge-green";
state_badge(~"executing") -> ~"badge-blue";
state_badge(~"available") -> ~"badge-blue";
state_badge(~"retryable") -> ~"badge-yellow";
state_badge(~"discarded") -> ~"badge-red";
state_badge(~"cancelled") -> ~"badge-gray";
state_badge(_) -> ~"".
