-module(shigoto_board_html).
-moduledoc """
Server-rendered HTML for the Shigoto board (iolist builders, Datastar-driven).

The `*_html/N` functions each render the *inner* of the `#page` live region;
`shigoto_board_page_controller` uses them for the first paint and
`shigoto_board_sse` re-emits the same inner every refresh tick, so first paint
and live patches always agree. `page/3` wraps a region in the full shell.

Interactivity is CSP-clean: filters are a plain GET form, pagination is plain
links, and only mutations (pause/resume/retry/cancel) and row-expand use
Datastar `data-on-click` (the CSP allows `script-src 'self' 'unsafe-eval'` for
Datastar's expression evaluation, but no inline `on*=` handlers).
""".

-export([
    page/3,
    csp_headers/0,
    overview_html/4,
    queues_html/1,
    workers_html/1,
    jobs_html/2,
    batches_html/1,
    cron_html/1,
    failures_html/1
]).

-define(PAGE_SIZE, 25).

-define(NAV, [
    {~"", ~"Overview"},
    {~"queues", ~"Queues"},
    {~"workers", ~"Workers"},
    {~"jobs", ~"Jobs"},
    {~"batches", ~"Batches"},
    {~"cron", ~"Cron"},
    {~"failures", ~"Failures"}
]).

%% ---------------------------------------------------------------------------
%% shell
%% ---------------------------------------------------------------------------

-doc "Full page shell around a live region. StreamPath opens the SSE stream.".
-spec page(binary(), binary() | none, iodata()) -> iodata().
page(Active, StreamPath, Inner) ->
    P = shigoto_board:prefix(),
    [
        ~"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">",
        ~"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        ~"<title>Shigoto Board \x{00B7} ",
        page_title(Active),
        ~"</title><link rel=\"stylesheet\" href=\"",
        P,
        ~"/assets/css/shigoto_board.css\">",
        ~"<script type=\"module\" src=\"",
        P,
        ~"/assets/js/datastar.js\"></script></head><body>",
        nav(P, Active),
        ~"<main class=\"main\">",
        stage(StreamPath, Inner),
        ~"</main></body></html>"
    ].

stage(none, Inner) ->
    [~"<div id=\"page\">", Inner, ~"</div>"];
stage(StreamPath, Inner) ->
    [
        ~"<div data-init=\"@get('",
        StreamPath,
        ~"')\"><div id=\"page\">",
        Inner,
        ~"</div></div>"
    ].

nav(P, Active) ->
    Links = [nav_item(P, Active, Page, Label) || {Page, Label} <- ?NAV],
    [
        ~"<nav class=\"nav\"><span class=\"nav-brand\">Shigoto</span>",
        ~"<div class=\"nav-links\">",
        Links,
        ~"</div></nav>"
    ].

nav_item(P, Active, Page, Label) ->
    Cls =
        case Page =:= Active of
            true -> ~"active";
            false -> ~""
        end,
    [
        ~"<a href=\"",
        P,
        ~"/",
        Page,
        ~"\" class=\"",
        Cls,
        ~"\">",
        Label,
        ~"</a>"
    ].

page_title(~"") -> ~"Overview";
page_title(Page) -> capitalise(Page).

-spec csp_headers() -> map().
csp_headers() ->
    #{
        ~"content-type" => ~"text/html; charset=utf-8",
        ~"cache-control" => ~"no-store",
        ~"content-security-policy" =>
            ~"default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"
    }.

%% ---------------------------------------------------------------------------
%% overview
%% ---------------------------------------------------------------------------

overview_html(Counts, Queues, Workers, StaleCount) ->
    [
        refresh_info(),
        stale_alert(StaleCount),
        ~"<div class=\"stat-grid\">",
        stat_card(~"Available", ~"text-blue", maps:get(available, Counts, 0)),
        stat_card(~"Executing", ~"text-amber", maps:get(executing, Counts, 0)),
        stat_card(~"Retryable", ~"text-yellow", maps:get(retryable, Counts, 0)),
        stat_card(~"Completed", ~"text-green", maps:get(completed, Counts, 0)),
        stat_card(~"Discarded", ~"text-red", maps:get(discarded, Counts, 0)),
        stat_card(~"Cancelled", ~"", maps:get(cancelled, Counts, 0)),
        ~"</div>",
        card(
            ~"Queues",
            table(
                [~"Queue", ~"Available", ~"Executing", ~"Retryable"],
                [~"", ~"text-right", ~"text-right", ~"text-right"],
                [overview_queue_row(Q) || Q <- Queues]
            )
        ),
        card(
            ~"Workers",
            table(
                [~"Worker", ~"Total", ~"Executing", ~"Completed", ~"Discarded"],
                [~"", ~"text-right", ~"text-right", ~"text-right", ~"text-right"],
                [overview_worker_row(W) || W <- Workers]
            )
        )
    ].

overview_queue_row(Q) ->
    row([
        {~"", esc(fmt(maps:get(queue, Q, ~"")))},
        {~"text-right", fmt(maps:get(available, Q, 0))},
        {~"text-right", fmt(maps:get(executing, Q, 0))},
        {~"text-right", fmt(maps:get(retryable, Q, 0))}
    ]).

overview_worker_row(W) ->
    row([
        {~"mono", esc(fmt(maps:get(worker, W, ~"unknown")))},
        {~"text-right", fmt(maps:get(total, W, 0))},
        {~"text-right", fmt(maps:get(executing, W, 0))},
        {~"text-right", fmt(maps:get(completed, W, 0))},
        {~"text-right", fmt(maps:get(discarded, W, 0))}
    ]).

%% ---------------------------------------------------------------------------
%% queues
%% ---------------------------------------------------------------------------

queues_html(Queues) ->
    P = shigoto_board:prefix(),
    [
        refresh_info(),
        card(
            ~"Queues",
            table(
                [~"Queue", ~"Status", ~"Available", ~"Executing", ~"Retryable", ~"Actions"],
                [~"", ~"", ~"text-right", ~"text-right", ~"text-right", ~""],
                [queue_row(P, Q) || Q <- Queues]
            )
        )
    ].

queue_row(P, Q) ->
    QName = fmt(maps:get(queue, Q, ~"")),
    IsPaused = maps:get(is_paused, Q, false),
    row([
        {~"", esc(QName)},
        {~"", status_badge(IsPaused)},
        {~"text-right", fmt(maps:get(available, Q, 0))},
        {~"text-right", fmt(maps:get(executing, Q, 0))},
        {~"text-right", fmt(maps:get(retryable, Q, 0))},
        {~"", queue_actions(P, QName)}
    ]).

status_badge(true) -> ~"<span class=\"badge badge-yellow\">paused</span>";
status_badge(_) -> ~"<span class=\"badge badge-green\">active</span>".

queue_actions(P, QName) ->
    Q = esc(QName),
    [
        ~"<button class=\"btn btn-sm btn-red\" data-on-click=\"@post('",
        P,
        ~"/queues/",
        Q,
        ~"/pause')\">Pause</button> ",
        ~"<button class=\"btn btn-sm btn-green\" data-on-click=\"@post('",
        P,
        ~"/queues/",
        Q,
        ~"/resume')\">Resume</button>"
    ].

%% ---------------------------------------------------------------------------
%% workers
%% ---------------------------------------------------------------------------

workers_html([]) ->
    [refresh_info(), card(~"Workers", ~"<p class=\"empty\">No worker data available</p>")];
workers_html(Workers) ->
    Title = [~"Workers ", count_badge(~"badge-blue", length(Workers))],
    [
        refresh_info(),
        card(
            Title,
            table(
                [
                    ~"Worker",
                    ~"Total",
                    ~"Available",
                    ~"Executing",
                    ~"Completed",
                    ~"Retryable",
                    ~"Discarded"
                ],
                [
                    ~"",
                    ~"text-right",
                    ~"text-right",
                    ~"text-right",
                    ~"text-right",
                    ~"text-right",
                    ~"text-right"
                ],
                [worker_row(W) || W <- Workers]
            )
        )
    ].

worker_row(W) ->
    row([
        {~"mono", esc(fmt(maps:get(worker, W, ~"unknown")))},
        {~"text-right", fmt(maps:get(total, W, 0))},
        {~"text-right", fmt(maps:get(available, W, 0))},
        {~"text-right", fmt(maps:get(executing, W, 0))},
        {~"text-right", fmt(maps:get(completed, W, 0))},
        {~"text-right", fmt(maps:get(retryable, W, 0))},
        {~"text-right", fmt(maps:get(discarded, W, 0))}
    ]).

%% ---------------------------------------------------------------------------
%% batches
%% ---------------------------------------------------------------------------

batches_html([]) ->
    [refresh_info(), card(~"Active Batches", ~"<p class=\"empty\">No active batches</p>")];
batches_html(Batches) ->
    [
        refresh_info(),
        card(
            ~"Active Batches",
            table(
                [
                    ~"ID",
                    ~"Callback",
                    ~"State",
                    ~"Progress",
                    ~"Completed",
                    ~"Discarded",
                    ~"Total"
                ],
                [~"", ~"", ~"", ~"", ~"text-right", ~"text-right", ~"text-right"],
                [batch_row(B) || B <- Batches]
            )
        )
    ].

batch_row(B) ->
    Total = maps:get(total_jobs, B, 0),
    Done = maps:get(completed_jobs, B, 0) + maps:get(discarded_jobs, B, 0),
    Pct =
        case Total of
            0 -> 0;
            _ -> (Done * 100) div Total
        end,
    row([
        {~"mono", fmt(maps:get(id, B, 0))},
        {~"mono", esc(fmt_callback(maps:get(callback_worker, B, null)))},
        {~"", [~"<span class=\"badge\">", esc(fmt(maps:get(state, B, ~"active"))), ~"</span>"]},
        {~"", progress_bar(Pct)},
        {~"text-right", fmt(maps:get(completed_jobs, B, 0))},
        {~"text-right", fmt(maps:get(discarded_jobs, B, 0))},
        {~"text-right", fmt(Total)}
    ]).

progress_bar(Pct) ->
    [
        ~"<div class=\"bar\"><div class=\"bar-fill bar-fill-green\" style=\"width:",
        integer_to_binary(Pct),
        ~"%\"></div></div>"
    ].

%% ---------------------------------------------------------------------------
%% cron (static page - no live refresh)
%% ---------------------------------------------------------------------------

cron_html([]) ->
    card(~"Cron Entries", ~"<p class=\"empty\">No cron entries configured</p>");
cron_html(Entries) ->
    Title = [~"Cron Entries ", count_badge(~"badge-blue", length(Entries))],
    card(
        Title,
        table(
            [~"Name", ~"Schedule", ~"Worker", ~"Queue"],
            [~"", ~"mono", ~"mono", ~""],
            [cron_row(E) || E <- Entries]
        )
    ).

cron_row({Name, Schedule, Worker, _Args}) ->
    row([
        {~"", esc(fmt(Name))},
        {~"mono", esc(fmt(Schedule))},
        {~"mono", esc(fmt(Worker))},
        {~"", esc(worker_queue(Worker))}
    ]).

worker_queue(Worker) when is_atom(Worker) ->
    try Worker:queue() of
        Q when is_binary(Q) -> Q;
        _ -> ~"default"
    catch
        _:_ -> ~"default"
    end;
worker_queue(_) ->
    ~"default".

%% ---------------------------------------------------------------------------
%% failures (stale jobs)
%% ---------------------------------------------------------------------------

failures_html([]) ->
    [refresh_info(), card(~"Stale Jobs", ~"<p class=\"empty\">No stale jobs detected</p>")];
failures_html(Stale) ->
    N = length(Stale),
    Title = [~"Stale Jobs ", count_badge(~"badge-red", N)],
    [
        refresh_info(),
        ~"<div class=\"alert alert-red\">",
        integer_to_binary(N),
        ~" stale job(s) detected - these may be zombie processes</div>",
        card(
            Title,
            table(
                [~"ID", ~"Worker", ~"Queue", ~"Attempt", ~"Last Heartbeat"],
                [~"mono", ~"mono", ~"", ~"text-right", ~"text-red"],
                [stale_row(J) || J <- Stale]
            )
        )
    ].

stale_row(J) ->
    row([
        {~"mono", fmt(maps:get(id, J, 0))},
        {~"mono", esc(fmt(maps:get(worker, J, ~"unknown")))},
        {~"", esc(fmt(maps:get(queue, J, ~"default")))},
        {~"text-right", fmt(maps:get(attempt, J, 0))},
        {~"text-red", fmt_timestamp(maps:get(heartbeat_at, J, null))}
    ]).

%% ---------------------------------------------------------------------------
%% jobs
%% ---------------------------------------------------------------------------

jobs_html(Jobs, Filters) ->
    P = shigoto_board:prefix(),
    Page = maps:get(page, Filters, 1),
    HasNext = length(Jobs) =:= ?PAGE_SIZE,
    FilterQs = filter_qs(Filters),
    ActionQs = page_qs(FilterQs, Page),
    [
        refresh_info(),
        filter_bar(P, Filters),
        card(
            [~"Jobs ", count_badge(~"badge-blue", [~"Page ", integer_to_binary(Page)])],
            [
                jobs_table(P, Jobs, ActionQs),
                pagination(P, Page, HasNext, FilterQs)
            ]
        )
    ].

filter_bar(P, Filters) ->
    FS = maps:get(filter_state, Filters, ~""),
    FQ = maps:get(filter_queue, Filters, ~""),
    FW = maps:get(filter_worker, Filters, ~""),
    [
        ~"<div class=\"card filter-bar\"><form class=\"filter-row\" method=\"get\" action=\"",
        P,
        ~"/jobs\">",
        filter_group(
            ~"State",
            [
                ~"<select class=\"filter-select\" name=\"state\">",
                state_option(FS, ~"", ~"All"),
                state_option(FS, ~"available", ~"Available"),
                state_option(FS, ~"executing", ~"Executing"),
                state_option(FS, ~"retryable", ~"Retryable"),
                state_option(FS, ~"completed", ~"Completed"),
                state_option(FS, ~"discarded", ~"Discarded"),
                state_option(FS, ~"cancelled", ~"Cancelled"),
                ~"</select>"
            ]
        ),
        filter_group(
            ~"Queue",
            [
                ~"<input class=\"filter-input\" type=\"text\" name=\"queue\" placeholder=\"e.g. default\" value=\"",
                esc(FQ),
                ~"\">"
            ]
        ),
        filter_group(
            ~"Worker",
            [
                ~"<input class=\"filter-input\" type=\"text\" name=\"worker\" placeholder=\"e.g. my_worker\" value=\"",
                esc(FW),
                ~"\">"
            ]
        ),
        ~"<div class=\"filter-group\"><label class=\"filter-label\">&nbsp;</label>",
        ~"<button class=\"btn btn-sm\" type=\"submit\">Filter</button></div>",
        ~"</form></div>"
    ].

filter_group(Label, Control) ->
    [
        ~"<div class=\"filter-group\"><label class=\"filter-label\">",
        Label,
        ~"</label>",
        Control,
        ~"</div>"
    ].

state_option(Current, Value, Label) ->
    Sel =
        case Current =:= Value of
            true -> ~" selected";
            false -> ~""
        end,
    [~"<option value=\"", Value, ~"\"", Sel, ~">", Label, ~"</option>"].

jobs_table(_P, [], _FilterQs) ->
    ~"<p class=\"empty\">No jobs match the current filters</p>";
jobs_table(P, Jobs, FilterQs) ->
    Now = erlang:universaltime(),
    [
        ~"<table><thead><tr><th></th><th>ID</th><th>Worker</th><th>Queue</th><th>State</th>",
        ~"<th class=\"text-right\">Attempt</th><th>Inserted</th><th>Actions</th></tr></thead><tbody>",
        [job_rows(P, Job, Now, FilterQs) || Job <- Jobs],
        ~"</tbody></table>"
    ].

job_rows(P, Job, Now, FilterQs) ->
    JobId = maps:get(id, Job, 0),
    IdBin = integer_to_binary(JobId),
    Sig = [~"$_open_", IdBin],
    JobState = fmt(maps:get(state, Job, ~"unknown")),
    [
        ~"<tr class=\"job-row\" data-on-click=\"",
        Sig,
        ~" = !",
        Sig,
        ~"\">",
        ~"<td class=\"expand-col\">\x{25B6}</td>",
        td(~"mono", IdBin),
        td(~"mono", esc(fmt(maps:get(worker, Job, ~"unknown")))),
        td(~"", esc(fmt(maps:get(queue, Job, ~"default")))),
        td(~"", [~"<span class=\"badge ", state_badge(JobState), ~"\">", esc(JobState), ~"</span>"]),
        td(~"text-right", [
            integer_to_binary(maps:get(attempt, Job, 0)),
            ~"/",
            integer_to_binary(maps:get(max_attempts, Job, 3))
        ]),
        td(~"text-dim", time_ago(maps:get(inserted_at, Job, undefined), Now)),
        ~"<td class=\"actions-cell\">",
        job_actions(P, JobState, IdBin, FilterQs),
        ~"</td></tr>",
        detail_row(Sig, Job)
    ].

job_actions(P, State, IdBin, FilterQs) when State =:= ~"retryable"; State =:= ~"discarded" ->
    Retry = action_button(~"btn-green", ~"Retry", P, IdBin, ~"retry", FilterQs),
    case State of
        ~"retryable" ->
            [Retry, ~" ", action_button(~"btn-red", ~"Cancel", P, IdBin, ~"cancel", FilterQs)];
        _ ->
            Retry
    end;
job_actions(P, State, IdBin, FilterQs) when State =:= ~"available"; State =:= ~"executing" ->
    action_button(~"btn-red", ~"Cancel", P, IdBin, ~"cancel", FilterQs);
job_actions(_P, _State, _IdBin, _FilterQs) ->
    ~"".

action_button(Cls, Label, P, IdBin, Action, FilterQs) ->
    [
        ~"<button class=\"btn btn-sm ",
        Cls,
        ~"\" data-on-click=\"@post('",
        P,
        ~"/jobs/",
        IdBin,
        ~"/",
        Action,
        FilterQs,
        ~"')\">",
        Label,
        ~"</button>"
    ].

detail_row(Sig, Job) ->
    Args = fmt_json(maps:get(args, Job, ~"{}")),
    Meta = fmt_json(maps:get(meta, Job, ~"{}")),
    Errors = format_errors(maps:get(errors, Job, [])),
    [
        ~"<tr class=\"detail-row\" data-show=\"",
        Sig,
        ~"\"><td colspan=\"8\"><div class=\"detail-grid\">",
        detail_section(~"Args", [~"<pre class=\"detail-pre\">", esc(Args), ~"</pre>"]),
        detail_section(~"Timestamps", [
            detail_kv(~"Inserted", fmt_timestamp(maps:get(inserted_at, Job, undefined))),
            detail_kv(~"Scheduled", fmt_timestamp(maps:get(scheduled_at, Job, undefined))),
            detail_kv(~"Attempted", fmt_timestamp(maps:get(attempted_at, Job, undefined))),
            detail_kv(~"Completed", fmt_timestamp(maps:get(completed_at, Job, undefined)))
        ]),
        detail_section(~"Meta", [
            detail_kv(~"Progress", [integer_to_binary(maps:get(progress, Job, 0)), ~"%"]),
            detail_kv(~"Tags", fmt_tags(maps:get(tags, Job, []))),
            ~"<pre class=\"detail-pre\">",
            esc(Meta),
            ~"</pre>"
        ]),
        errors_section(Errors),
        ~"</div></td></tr>"
    ].

detail_section(Label, Body) ->
    [
        ~"<div class=\"detail-section\"><div class=\"detail-label\">",
        Label,
        ~"</div>",
        Body,
        ~"</div>"
    ].

detail_kv(Key, Value) ->
    [
        ~"<div class=\"detail-kv\"><span class=\"detail-key\">",
        Key,
        ~":</span> <span>",
        Value,
        ~"</span></div>"
    ].

errors_section([]) ->
    ~"";
errors_section(Errors) ->
    [
        ~"<div class=\"detail-section detail-section-full\"><div class=\"detail-label\">Error History (",
        integer_to_binary(length(Errors)),
        ~")</div>",
        [error_entry(E) || E <- Errors],
        ~"</div>"
    ].

error_entry(ErrMap) ->
    Attempt = fmt(maps:get(~"attempt", ErrMap, maps:get(attempt, ErrMap, ~"?"))),
    Msg = fmt(maps:get(~"error", ErrMap, maps:get(error, ErrMap, ~"unknown"))),
    [
        ~"<div class=\"error-entry\"><span class=\"error-attempt\">Attempt ",
        esc(Attempt),
        ~"</span><pre class=\"detail-pre error-msg\">",
        esc(Msg),
        ~"</pre></div>"
    ].

pagination(P, Page, HasNext, FilterQs) ->
    [
        ~"<div class=\"pagination\">",
        page_link(P, ~"Previous", Page > 1, page_qs(FilterQs, Page - 1)),
        ~"<span class=\"page-info\">Page ",
        integer_to_binary(Page),
        ~"</span>",
        page_link(P, ~"Next", HasNext, page_qs(FilterQs, Page + 1)),
        ~"</div>"
    ].

page_link(_P, Label, false, _Qs) ->
    [~"<button class=\"btn btn-sm\" disabled>", Label, ~"</button>"];
page_link(P, Label, true, Qs) ->
    [~"<a class=\"btn btn-sm\" href=\"", P, ~"/jobs", Qs, ~"\">", Label, ~"</a>"].

%% ---------------------------------------------------------------------------
%% query-string helpers (filters <-> URL)
%% ---------------------------------------------------------------------------

filter_qs(Filters) ->
    Pairs =
        qs_pair(~"state", maps:get(filter_state, Filters, ~"")) ++
            qs_pair(~"queue", maps:get(filter_queue, Filters, ~"")) ++
            qs_pair(~"worker", maps:get(filter_worker, Filters, ~"")),
    case Pairs of
        [] -> ~"";
        _ -> [~"?", lists:join(~"&", Pairs)]
    end.

page_qs(FilterQs, Page) ->
    PageBin = integer_to_binary(Page),
    case iolist_to_binary(FilterQs) of
        <<>> -> [~"?page=", PageBin];
        _ -> [FilterQs, ~"&page=", PageBin]
    end.

qs_pair(_Key, ~"") -> [];
qs_pair(Key, Value) -> [[Key, ~"=", uri_encode(Value)]].

uri_encode(Bin) ->
    list_to_binary(uri_string:quote(binary_to_list(Bin))).

%% ---------------------------------------------------------------------------
%% small shared render helpers
%% ---------------------------------------------------------------------------

refresh_info() ->
    ~"<p class=\"refresh-info\">Auto-refreshes live</p>".

card(Title, Body) ->
    [~"<div class=\"card\"><div class=\"card-title\">", Title, ~"</div>", Body, ~"</div>"].

count_badge(Cls, N) when is_integer(N) ->
    count_badge(Cls, integer_to_binary(N));
count_badge(Cls, Label) ->
    [~"<span class=\"badge ", Cls, ~"\">", Label, ~"</span>"].

stat_card(Label, ColorClass, Value) ->
    [
        ~"<div class=\"stat\"><div class=\"stat-label\">",
        Label,
        ~"</div><div class=\"stat-value ",
        ColorClass,
        ~"\">",
        fmt(Value),
        ~"</div></div>"
    ].

stale_alert(0) ->
    ~"";
stale_alert(Count) ->
    [
        ~"<div class=\"alert alert-red\">",
        integer_to_binary(Count),
        ~" stale job(s) detected - possible zombie processes</div>"
    ].

table(Headers, Classes, Rows) ->
    [
        ~"<table><thead><tr>",
        [th(C, H) || {C, H} <- lists:zip(Classes, Headers)],
        ~"</tr></thead><tbody>",
        Rows,
        ~"</tbody></table>"
    ].

th(~"", H) -> [~"<th>", H, ~"</th>"];
th(Cls, H) -> [~"<th class=\"", Cls, ~"\">", H, ~"</th>"].

row(Cells) ->
    [~"<tr>", [td(Cls, Body) || {Cls, Body} <- Cells], ~"</tr>"].

td(~"", Body) -> [~"<td>", Body, ~"</td>"];
td(Cls, Body) -> [~"<td class=\"", Cls, ~"\">", Body, ~"</td>"].

%% ---------------------------------------------------------------------------
%% formatting
%% ---------------------------------------------------------------------------

fmt(N) when is_integer(N) -> integer_to_binary(N);
fmt(V) when is_binary(V) -> V;
fmt(V) when is_atom(V) -> atom_to_binary(V);
fmt(V) -> iolist_to_binary(io_lib:format(~"~p", [V])).

fmt_callback(null) -> ~"-";
fmt_callback(V) when is_binary(V) -> V;
fmt_callback(V) when is_atom(V) -> atom_to_binary(V);
fmt_callback(_) -> ~"-".

state_badge(~"completed") -> ~"badge-green";
state_badge(~"executing") -> ~"badge-blue";
state_badge(~"available") -> ~"badge-blue";
state_badge(~"retryable") -> ~"badge-yellow";
state_badge(~"discarded") -> ~"badge-red";
state_badge(~"cancelled") -> ~"badge-gray";
state_badge(_) -> ~"".

capitalise(<<First, Rest/binary>>) when First >= $a, First =< $z ->
    <<(First - 32), Rest/binary>>;
capitalise(Bin) ->
    Bin.

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
    case binary:split(Bin, [~"T", ~" "]) of
        [DateBin, TimeBin] ->
            [Y, Mo, D] = [binary_to_integer(Pt) || Pt <- binary:split(DateBin, ~"-", [global])],
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
format_duration(S) when S < 60 -> <<(integer_to_binary(S))/binary, " ago">>;
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
fmt_timestamp(V) when is_binary(V) ->
    V;
fmt_timestamp(_) ->
    ~"-".

fmt_json(V) when is_binary(V) ->
    try
        Decoded = json:decode(V),
        iolist_to_binary(json:encode(Decoded))
    catch
        _:_ -> V
    end;
fmt_json(V) when is_map(V) ->
    try
        iolist_to_binary(json:encode(V))
    catch
        _:_ -> ~"{}"
    end;
fmt_json(_) ->
    ~"{}".

fmt_tags([]) ->
    ~"none";
fmt_tags(Tags) when is_list(Tags) ->
    iolist_to_binary(lists:join(~", ", [fmt(T) || T <- Tags]));
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

%% HTML-escape text for safe interpolation into element bodies and attributes.
esc(Bin) when is_binary(Bin) ->
    binary:replace(
        binary:replace(
            binary:replace(
                binary:replace(
                    binary:replace(Bin, ~"&", ~"&amp;", [global]),
                    ~"<",
                    ~"&lt;",
                    [global]
                ),
                ~">",
                ~"&gt;",
                [global]
            ),
            ~"\"",
            ~"&quot;",
            [global]
        ),
        ~"'",
        ~"&#39;",
        [global]
    );
esc(V) ->
    esc(fmt(V)).
