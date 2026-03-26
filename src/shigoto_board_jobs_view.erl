-module(shigoto_board_jobs_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    Filters = #{limit => 50, offset => 0},
    {ok, Jobs} = search_jobs(Filters),
    Prefix = shigoto_board:prefix(),
    Bindings = #{
        id => ~"jobs_view",
        jobs => Jobs,
        filters => Filters,
        filter_state => ~"",
        filter_queue => ~"",
        filter_worker => ~""
    },
    Layout =
        {shigoto_board_layout, render, main_content, #{
            active_page => ~"jobs",
            prefix => Prefix,
            ws_path => <<(arizona_nova:prefix())/binary, "/live">>,
            arizona_prefix => arizona_nova:prefix()
        }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Jobs = arizona_template:get_binding(jobs, Bindings),
    FilterState = arizona_template:get_binding(filter_state, Bindings),
    FilterQueue = arizona_template:get_binding(filter_queue, Bindings),
    FilterWorker = arizona_template:get_binding(filter_worker, Bindings),
    StateChange =
        <<"arizona.pushEventTo('jobs_view', 'filter', JSON.parse('{\"state\": \"' + this.value + '\"}'))">>,
    QueueChange =
        <<"arizona.pushEventTo('jobs_view', 'filter', JSON.parse('{\"queue\": \"' + this.value + '\"}'))">>,
    WorkerChange =
        <<"arizona.pushEventTo('jobs_view', 'filter', JSON.parse('{\"worker\": \"' + this.value + '\"}'))">>,
    arizona_template:from_html(
        ~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <p class="refresh-info">Auto-refreshes every 3s</p>

        <div class="card filter-bar">
            <div class="filter-row">
                <div class="filter-group">
                    <label class="filter-label">State</label>
                    <select class="filter-select" onchange="{StateChange}">
                        <option value="" {selected(FilterState, ~"")}>All</option>
                        <option value="available" {selected(FilterState, ~"available")}>Available</option>
                        <option value="executing" {selected(FilterState, ~"executing")}>Executing</option>
                        <option value="retryable" {selected(FilterState, ~"retryable")}>Retryable</option>
                        <option value="completed" {selected(FilterState, ~"completed")}>Completed</option>
                        <option value="discarded" {selected(FilterState, ~"discarded")}>Discarded</option>
                        <option value="cancelled" {selected(FilterState, ~"cancelled")}>Cancelled</option>
                    </select>
                </div>
                <div class="filter-group">
                    <label class="filter-label">Queue</label>
                    <input class="filter-input" type="text" placeholder="e.g. default"
                        value="{FilterQueue}"
                        onchange="{QueueChange}" />
                </div>
                <div class="filter-group">
                    <label class="filter-label">Worker</label>
                    <input class="filter-input" type="text" placeholder="e.g. my_worker"
                        value="{FilterWorker}"
                        onchange="{WorkerChange}" />
                </div>
            </div>
        </div>

        <div class="card">
            <div class="card-title">
                Jobs
                <span class="badge badge-blue">{integer_to_binary(length(Jobs))}</span>
            </div>
            {render_jobs_table(Jobs)}
        </div>
    </div>
    """
    ).

handle_event(~"filter", Params, View) ->
    State = arizona_view:get_state(View),
    Filters0 = arizona_stateful:get_binding(filters, State),
    FilterState0 = arizona_stateful:get_binding(filter_state, State),
    FilterQueue0 = arizona_stateful:get_binding(filter_queue, State),
    FilterWorker0 = arizona_stateful:get_binding(filter_worker, State),
    {Filters, FS, FQ, FW} = apply_filter_params(
        Params, Filters0, FilterState0, FilterQueue0, FilterWorker0
    ),
    {ok, Jobs} = search_jobs(Filters),
    S1 = arizona_stateful:put_binding(jobs, Jobs, State),
    S2 = arizona_stateful:put_binding(filters, Filters, S1),
    S3 = arizona_stateful:put_binding(filter_state, FS, S2),
    S4 = arizona_stateful:put_binding(filter_queue, FQ, S3),
    S5 = arizona_stateful:put_binding(filter_worker, FW, S4),
    {[], arizona_view:update_state(S5, View)};
handle_event(~"retry", #{~"job_id" := JobIdBin}, View) ->
    JobId = binary_to_integer(JobIdBin),
    Pool = shigoto_config:pool(),
    shigoto:retry(Pool, JobId),
    refresh_data(View);
handle_event(~"cancel", #{~"job_id" := JobIdBin}, View) ->
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
%% Rendering helpers
%%----------------------------------------------------------------------

render_jobs_table([]) ->
    arizona_template:from_html(
        ~"""
    <p class="empty">No jobs match the current filters</p>
    """
    );
render_jobs_table(Jobs) ->
    arizona_template:from_html(
        ~"""
    <table>
        <thead><tr>
            <th>ID</th>
            <th>Worker</th>
            <th>Queue</th>
            <th>State</th>
            <th class="text-right">Attempt</th>
            <th>Error</th>
            <th>Actions</th>
        </tr></thead>
        <tbody>
            {arizona_template:render_list(fun render_job_row/1, Jobs)}
        </tbody>
    </table>
    """
    ).

render_job_row(Job) ->
    IdBin = integer_to_binary(maps:get(id, Job)),
    Worker = fmt_bin(maps:get(worker, Job, ~"unknown")),
    Queue = fmt_bin(maps:get(queue, Job, ~"default")),
    JobState = fmt_bin(maps:get(state, Job, ~"unknown")),
    Attempt = integer_to_binary(maps:get(attempt, Job, 0)),
    MaxAttempts = integer_to_binary(maps:get(max_attempts, Job, 3)),
    LastError = extract_last_error(maps:get(errors, Job, [])),
    RetryClick = <<"arizona.pushEventTo('jobs_view', 'retry', {job_id: '", IdBin/binary, "'})">>,
    CancelClick = <<"arizona.pushEventTo('jobs_view', 'cancel', {job_id: '", IdBin/binary, "'})">>,
    arizona_template:from_html(
        ~"""
    <tr>
        <td class="mono">{IdBin}</td>
        <td class="mono">{Worker}</td>
        <td>{Queue}</td>
        <td><span class="badge {state_badge(JobState)}">{JobState}</span></td>
        <td class="text-right">{Attempt}/{MaxAttempts}</td>
        <td class="mono error-text">{truncate(LastError, 60)}</td>
        <td class="actions-cell">
            {action_buttons(JobState, RetryClick, CancelClick)}
        </td>
    </tr>
    """
    ).

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

search_jobs(Filters) ->
    shigoto_dashboard:search_jobs(Filters).

refresh_data(View) ->
    State = arizona_view:get_state(View),
    Filters = arizona_stateful:get_binding(filters, State),
    {ok, Jobs} = search_jobs(Filters),
    S1 = arizona_stateful:put_binding(jobs, Jobs, State),
    {[], arizona_view:update_state(S1, View)}.

apply_filter_params(Params, Filters0, FS0, FQ0, FW0) ->
    {Filters1, FS} =
        case maps:find(~"state", Params) of
            {ok, <<>>} -> {maps:remove(state, Filters0), ~""};
            {ok, S} -> {Filters0#{state => S}, S};
            error -> {Filters0, FS0}
        end,
    {Filters2, FQ} =
        case maps:find(~"queue", Params) of
            {ok, <<>>} -> {maps:remove(queue, Filters1), ~""};
            {ok, Q} -> {Filters1#{queue => Q}, Q};
            error -> {Filters1, FQ0}
        end,
    {Filters3, FW} =
        case maps:find(~"worker", Params) of
            {ok, <<>>} -> {maps:remove(worker, Filters2), ~""};
            {ok, W} -> {Filters2#{worker => W}, W};
            error -> {Filters2, FW0}
        end,
    {Filters3#{offset => 0}, FS, FQ, FW}.

action_buttons(~"retryable", RetryClick, CancelClick) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm btn-green" onclick="{RetryClick}">Retry</button>
    <button class="btn btn-sm btn-red" onclick="{CancelClick}">Cancel</button>
    """
    );
action_buttons(~"discarded", RetryClick, _CancelClick) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm btn-green" onclick="{RetryClick}">Retry</button>
    """
    );
action_buttons(~"available", _RetryClick, CancelClick) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm btn-red" onclick="{CancelClick}">Cancel</button>
    """
    );
action_buttons(~"executing", _RetryClick, CancelClick) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm btn-red" onclick="{CancelClick}">Cancel</button>
    """
    );
action_buttons(_, _, _) ->
    ~"".

extract_last_error(Errors) when is_binary(Errors) ->
    try
        case json:decode(Errors) of
            List when is_list(List), length(List) > 0 ->
                Last = lists:last(List),
                maps:get(~"error", Last, ~"");
            _ ->
                ~""
        end
    catch
        _:_ -> ~""
    end;
extract_last_error(Errors) when is_list(Errors), length(Errors) > 0 ->
    Last = lists:last(Errors),
    case is_map(Last) of
        true -> fmt_bin(maps:get(~"error", Last, maps:get(error, Last, ~"")));
        false -> ~""
    end;
extract_last_error(_) ->
    ~"".

truncate(<<>>, _) ->
    ~"";
truncate(Bin, Max) when byte_size(Bin) > Max ->
    <<(binary:part(Bin, 0, Max))/binary, "...">>;
truncate(Bin, _Max) ->
    Bin.

selected(Current, Value) when Current =:= Value -> ~"selected";
selected(_, _) -> ~"".

state_badge(~"completed") -> ~"badge-green";
state_badge(~"executing") -> ~"badge-blue";
state_badge(~"available") -> ~"badge-blue";
state_badge(~"retryable") -> ~"badge-yellow";
state_badge(~"discarded") -> ~"badge-red";
state_badge(~"cancelled") -> ~"badge-gray";
state_badge(_) -> ~"".

fmt_bin(V) when is_binary(V) -> V;
fmt_bin(V) when is_atom(V) -> atom_to_binary(V);
fmt_bin(_) -> ~"".
