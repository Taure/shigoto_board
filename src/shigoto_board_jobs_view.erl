-module(shigoto_board_jobs_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

-define(PAGE_SIZE, 25).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(3000, self(), refresh);
        false -> ok
    end,
    Filters = #{limit => ?PAGE_SIZE, offset => 0},
    {ok, Jobs} = search_jobs(Filters),
    Prefix = shigoto_board:prefix(),
    Bindings = #{
        id => ~"jobs_view",
        jobs => Jobs,
        filters => Filters,
        page => 1,
        filter_state => ~"",
        filter_queue => ~"",
        filter_worker => ~"",
        expanded => #{}
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
    Page = arizona_template:get_binding(page, Bindings),
    FilterState = arizona_template:get_binding(filter_state, Bindings),
    FilterQueue = arizona_template:get_binding(filter_queue, Bindings),
    FilterWorker = arizona_template:get_binding(filter_worker, Bindings),
    Expanded = arizona_template:get_binding(expanded, Bindings),
    StateChange =
        <<"arizona.pushEventTo('jobs_view', 'filter', JSON.parse('{\"state\": \"' + this.value + '\"}'))">>,
    QueueChange =
        <<"arizona.pushEventTo('jobs_view', 'filter', JSON.parse('{\"queue\": \"' + this.value + '\"}'))">>,
    WorkerChange =
        <<"arizona.pushEventTo('jobs_view', 'filter', JSON.parse('{\"worker\": \"' + this.value + '\"}'))">>,
    PrevClick = <<"arizona.pushEventTo('jobs_view', 'page', JSON.parse('{\"dir\": \"prev\"}'))">>,
    NextClick = <<"arizona.pushEventTo('jobs_view', 'page', JSON.parse('{\"dir\": \"next\"}'))">>,
    HasNext = length(Jobs) =:= ?PAGE_SIZE,
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
                <span class="badge badge-blue">Page {integer_to_binary(Page)}</span>
            </div>
            {render_jobs_table(Jobs, Expanded)}
            {render_pagination(Page, HasNext, PrevClick, NextClick)}
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
    S6 = arizona_stateful:put_binding(page, 1, S5),
    S7 = arizona_stateful:put_binding(expanded, #{}, S6),
    {[], arizona_view:update_state(S7, View)};
handle_event(~"page", #{~"dir" := Dir}, View) ->
    State = arizona_view:get_state(View),
    Page = arizona_stateful:get_binding(page, State),
    Filters0 = arizona_stateful:get_binding(filters, State),
    NewPage =
        case Dir of
            ~"next" -> Page + 1;
            ~"prev" -> max(1, Page - 1)
        end,
    Offset = (NewPage - 1) * ?PAGE_SIZE,
    Filters = Filters0#{offset => Offset},
    {ok, Jobs} = search_jobs(Filters),
    S1 = arizona_stateful:put_binding(jobs, Jobs, State),
    S2 = arizona_stateful:put_binding(filters, Filters, S1),
    S3 = arizona_stateful:put_binding(page, NewPage, S2),
    S4 = arizona_stateful:put_binding(expanded, #{}, S3),
    {[], arizona_view:update_state(S4, View)};
handle_event(~"toggle_detail", #{~"job_id" := JobIdBin}, View) ->
    JobId = binary_to_integer(JobIdBin),
    State = arizona_view:get_state(View),
    Expanded = arizona_stateful:get_binding(expanded, State),
    NewExpanded =
        case maps:is_key(JobId, Expanded) of
            true -> maps:remove(JobId, Expanded);
            false -> Expanded#{JobId => true}
        end,
    S1 = arizona_stateful:put_binding(expanded, NewExpanded, State),
    {[], arizona_view:update_state(S1, View)};
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

render_jobs_table([], _Expanded) ->
    arizona_template:from_html(
        ~"""
    <p class="empty">No jobs match the current filters</p>
    """
    );
render_jobs_table(Jobs, Expanded) ->
    Now = erlang:universaltime(),
    Rows = lists:flatmap(fun(Job) -> job_rows(Job, Expanded, Now) end, Jobs),
    arizona_template:from_html(
        ~"""
    <table>
        <thead><tr>
            <th></th>
            <th>ID</th>
            <th>Worker</th>
            <th>Queue</th>
            <th>State</th>
            <th class="text-right">Attempt</th>
            <th>Inserted</th>
            <th>Actions</th>
        </tr></thead>
        <tbody>
            {arizona_template:render_list(fun render_row_item/1, Rows)}
        </tbody>
    </table>
    """
    ).

job_rows(Job, Expanded, Now) ->
    JobId = maps:get(id, Job),
    IsExpanded = maps:is_key(JobId, Expanded),
    case IsExpanded of
        false -> [{row, Job, Now}];
        true -> [{row, Job, Now}, {detail, Job, Now}]
    end.

render_row_item({row, Job, Now}) ->
    render_job_row(Job, Now);
render_row_item({detail, Job, Now}) ->
    render_detail_row(Job, Now).

render_job_row(Job, Now) ->
    IdBin = integer_to_binary(maps:get(id, Job)),
    Worker = fmt_bin(maps:get(worker, Job, ~"unknown")),
    Queue = fmt_bin(maps:get(queue, Job, ~"default")),
    JobState = fmt_bin(maps:get(state, Job, ~"unknown")),
    Attempt = integer_to_binary(maps:get(attempt, Job, 0)),
    MaxAttempts = integer_to_binary(maps:get(max_attempts, Job, 3)),
    InsertedAgo = time_ago(maps:get(inserted_at, Job, undefined), Now),
    ToggleClick =
        <<"arizona.pushEventTo('jobs_view', 'toggle_detail', JSON.parse('{\"job_id\": \"",
            IdBin/binary, "\"}'))">>,
    RetryClick =
        <<"arizona.pushEventTo('jobs_view', 'retry', JSON.parse('{\"job_id\": \"", IdBin/binary,
            "\"}'))">>,
    CancelClick =
        <<"arizona.pushEventTo('jobs_view', 'cancel', JSON.parse('{\"job_id\": \"", IdBin/binary,
            "\"}'))">>,
    arizona_template:from_html(
        ~"""
    <tr class="job-row" onclick="{ToggleClick}">
        <td class="expand-col">&#9654;</td>
        <td class="mono">{IdBin}</td>
        <td class="mono">{Worker}</td>
        <td>{Queue}</td>
        <td><span class="badge {state_badge(JobState)}">{JobState}</span></td>
        <td class="text-right">{Attempt}/{MaxAttempts}</td>
        <td class="text-dim">{InsertedAgo}</td>
        <td class="actions-cell" onclick="event.stopPropagation()">
            {action_buttons(JobState, RetryClick, CancelClick)}
        </td>
    </tr>
    """
    ).

render_detail_row(Job, _Now) ->
    IdBin = integer_to_binary(maps:get(id, Job)),
    Args = fmt_json(maps:get(args, Job, ~"{}")),
    Errors = format_errors(maps:get(errors, Job, [])),
    Meta = fmt_json(maps:get(meta, Job, ~"{}")),
    InsertedAt = fmt_timestamp(maps:get(inserted_at, Job, undefined)),
    AttemptedAt = fmt_timestamp(maps:get(attempted_at, Job, undefined)),
    CompletedAt = fmt_timestamp(maps:get(completed_at, Job, undefined)),
    ScheduledAt = fmt_timestamp(maps:get(scheduled_at, Job, undefined)),
    Progress = maps:get(progress, Job, 0),
    ProgressBin = integer_to_binary(Progress),
    Tags = fmt_tags(maps:get(tags, Job, [])),
    ToggleClick =
        <<"arizona.pushEventTo('jobs_view', 'toggle_detail', JSON.parse('{\"job_id\": \"",
            IdBin/binary, "\"}'))">>,
    arizona_template:from_html(
        ~"""
    <tr class="detail-row" onclick="{ToggleClick}">
        <td colspan="8">
            <div class="detail-grid">
                <div class="detail-section">
                    <div class="detail-label">Args</div>
                    <pre class="detail-pre">{Args}</pre>
                </div>
                <div class="detail-section">
                    <div class="detail-label">Timestamps</div>
                    <div class="detail-kv">
                        <span class="detail-key">Inserted:</span> <span>{InsertedAt}</span>
                    </div>
                    <div class="detail-kv">
                        <span class="detail-key">Scheduled:</span> <span>{ScheduledAt}</span>
                    </div>
                    <div class="detail-kv">
                        <span class="detail-key">Attempted:</span> <span>{AttemptedAt}</span>
                    </div>
                    <div class="detail-kv">
                        <span class="detail-key">Completed:</span> <span>{CompletedAt}</span>
                    </div>
                </div>
                <div class="detail-section">
                    <div class="detail-label">Meta</div>
                    <div class="detail-kv">
                        <span class="detail-key">Progress:</span>
                        <span>{ProgressBin}%</span>
                    </div>
                    <div class="detail-kv">
                        <span class="detail-key">Tags:</span>
                        <span>{Tags}</span>
                    </div>
                    <pre class="detail-pre">{Meta}</pre>
                </div>
                {render_errors_section(Errors)}
            </div>
        </td>
    </tr>
    """
    ).

render_errors_section([]) ->
    ~"";
render_errors_section(Errors) ->
    arizona_template:from_html(
        ~"""
    <div class="detail-section detail-section-full">
        <div class="detail-label">Error History ({integer_to_binary(length(Errors))})</div>
        {arizona_template:render_list(fun render_error_entry/1, Errors)}
    </div>
    """
    ).

render_error_entry(ErrMap) ->
    AttemptBin = fmt_bin(maps:get(~"attempt", ErrMap, maps:get(attempt, ErrMap, ~"?"))),
    ErrorMsg = fmt_bin(maps:get(~"error", ErrMap, maps:get(error, ErrMap, ~"unknown"))),
    arizona_template:from_html(
        ~"""
    <div class="error-entry">
        <span class="error-attempt">Attempt {AttemptBin}</span>
        <pre class="detail-pre error-msg">{ErrorMsg}</pre>
    </div>
    """
    ).

render_pagination(Page, HasNext, PrevClick, NextClick) ->
    arizona_template:from_html(
        ~"""
    <div class="pagination">
        {prev_button(Page, PrevClick)}
        <span class="page-info">Page {integer_to_binary(Page)}</span>
        {next_button(HasNext, NextClick)}
    </div>
    """
    ).

prev_button(1, _Click) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm" disabled>Previous</button>
    """
    );
prev_button(_Page, Click) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm" onclick="{Click}">Previous</button>
    """
    ).

next_button(false, _Click) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm" disabled>Next</button>
    """
    );
next_button(true, Click) ->
    arizona_template:from_html(
        ~"""
    <button class="btn btn-sm" onclick="{Click}">Next</button>
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

%%----------------------------------------------------------------------
%% Formatting
%%----------------------------------------------------------------------

time_ago(undefined, _Now) ->
    ~"-";
time_ago(null, _Now) ->
    ~"-";
time_ago(Timestamp, Now) ->
    try
        Seconds =
            calendar:datetime_to_gregorian_seconds(Now) -
                calendar:datetime_to_gregorian_seconds(to_datetime(Timestamp)),
        format_duration(Seconds)
    catch
        _:_ -> ~"-"
    end.

to_datetime({{_, _, _}, {_, _, _}} = DT) ->
    DT;
to_datetime(Bin) when is_binary(Bin) ->
    %% Try parsing ISO 8601 from binary
    case binary:split(Bin, [~"T", ~" "]) of
        [DateBin, TimeBin] ->
            [Y, Mo, D] = [binary_to_integer(P) || P <- binary:split(DateBin, ~"-", [global])],
            TimeClean = hd(binary:split(TimeBin, [~"+", ~"Z"])),
            [H, Mi | Rest] = binary:split(TimeClean, ~":", [global]),
            S =
                case Rest of
                    [SBin] -> binary_to_integer(hd(binary:split(SBin, ~".")));
                    [] -> 0
                end,
            {{Y, Mo, D}, {binary_to_integer(H), binary_to_integer(Mi), S}};
        _ ->
            erlang:universaltime()
    end;
to_datetime(_) ->
    erlang:universaltime().

format_duration(S) when S < 0 -> ~"just now";
format_duration(S) when S < 60 -> <<(integer_to_binary(S))/binary, "s ago">>;
format_duration(S) when S < 3600 -> <<(integer_to_binary(S div 60))/binary, "m ago">>;
format_duration(S) when S < 86400 -> <<(integer_to_binary(S div 3600))/binary, "h ago">>;
format_duration(S) -> <<(integer_to_binary(S div 86400))/binary, "d ago">>.

fmt_timestamp(undefined) ->
    ~"-";
fmt_timestamp(null) ->
    ~"-";
fmt_timestamp({{Y, Mo, D}, {H, Mi, S}}) ->
    iolist_to_binary(
        io_lib:format(~"~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", [Y, Mo, D, H, Mi, S])
    );
fmt_timestamp(V) when is_binary(V) -> V;
fmt_timestamp(_) ->
    ~"-".

fmt_json(V) when is_binary(V) ->
    try
        Decoded = json:decode(V),
        iolist_to_binary(json:encode(Decoded, #{indent => 2}))
    catch
        _:_ -> V
    end;
fmt_json(V) when is_map(V) ->
    try
        iolist_to_binary(json:encode(V, #{indent => 2}))
    catch
        _:_ -> ~"{}"
    end;
fmt_json(_) ->
    ~"{}".

fmt_tags([]) ->
    ~"none";
fmt_tags(Tags) when is_list(Tags) ->
    iolist_to_binary(lists:join(~", ", [fmt_bin(T) || T <- Tags]));
fmt_tags(V) when is_binary(V) ->
    try
        case json:decode(V) of
            List when is_list(List) -> fmt_tags(List);
            _ -> V
        end
    catch
        _:_ -> V
    end;
fmt_tags(_) ->
    ~"none".

format_errors(Errors) when is_binary(Errors) ->
    try
        case json:decode(Errors) of
            List when is_list(List) -> List;
            _ -> []
        end
    catch
        _:_ -> []
    end;
format_errors(Errors) when is_list(Errors) ->
    Errors;
format_errors(_) ->
    [].

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
fmt_bin(V) when is_integer(V) -> integer_to_binary(V);
fmt_bin(_) -> ~"".
