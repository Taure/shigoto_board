-module(shigoto_board_page_controller).
-moduledoc """
Nova controllers for the board pages.

Each page server-renders the full shell (`shigoto_board_html:page/3`) with a
first-paint snapshot and a `data-init` stream path; the stream
(`shigoto_board_sse`) then repaints the live region. `page_inner/2` is the
single place that maps a page to its data + HTML, so the first paint and the
live patches always agree. Cron is a static page (no stream).
""".

-export([
    index/1,
    queues/1,
    workers/1,
    jobs/1,
    batches/1,
    cron/1,
    failures/1,
    dlq/1,
    page_inner/2,
    page_atom/1,
    filters_from_qs/1
]).

-define(PAGE_SIZE, 25).

%% ---------------------------------------------------------------------------
%% controllers
%% ---------------------------------------------------------------------------

index(_Req) ->
    full(~"", stream_path(~"overview"), page_inner(overview, undefined)).

queues(_Req) ->
    full(~"queues", stream_path(~"queues"), page_inner(queues, undefined)).

workers(_Req) ->
    full(~"workers", stream_path(~"workers"), page_inner(workers, undefined)).

batches(_Req) ->
    full(~"batches", stream_path(~"batches"), page_inner(batches, undefined)).

failures(_Req) ->
    full(~"failures", stream_path(~"failures"), page_inner(failures, undefined)).

dlq(_Req) ->
    full(~"dlq", stream_path(~"dlq"), page_inner(dlq, undefined)).

cron(_Req) ->
    %% Static page - cron entries are config, not runtime state.
    full(~"cron", none, page_inner(cron, undefined)).

jobs(Req) ->
    Filters = filters_from_qs(cowboy_req:parse_qs(Req)),
    full(~"jobs", jobs_stream_path(Filters), page_inner(jobs, Filters)).

%% ---------------------------------------------------------------------------
%% shared render dispatch
%% ---------------------------------------------------------------------------

-doc "Map a page to its freshly-gathered data, rendered to the live region inner.".
-spec page_inner(atom(), term()) -> iodata().
page_inner(overview, _) ->
    Counts = ok_map(shigoto_dashboard:job_counts()),
    Queues = ok_list(shigoto_dashboard:queue_stats()),
    Workers = ok_list(shigoto_dashboard:worker_stats()),
    Stale = ok_list(shigoto_dashboard:stale_jobs()),
    shigoto_board_html:overview_html(Counts, Queues, Workers, length(Stale));
page_inner(queues, _) ->
    shigoto_board_html:queues_html(ok_list(shigoto_dashboard:queue_stats()));
page_inner(workers, _) ->
    shigoto_board_html:workers_html(ok_list(shigoto_dashboard:worker_stats()));
page_inner(batches, _) ->
    shigoto_board_html:batches_html(ok_list(shigoto_dashboard:batch_stats()));
page_inner(failures, _) ->
    shigoto_board_html:failures_html(ok_list(shigoto_dashboard:stale_jobs()));
page_inner(dlq, _) ->
    Discarded = ok_list(
        shigoto_dashboard:search_jobs(#{state => ~"discarded", limit => ?PAGE_SIZE})
    ),
    shigoto_board_html:dlq_html(Discarded);
page_inner(cron, _) ->
    shigoto_board_html:cron_html(shigoto_config:cron_entries());
page_inner(jobs, Filters) when is_map(Filters) ->
    Jobs = ok_list(shigoto_dashboard:search_jobs(search_map(Filters))),
    shigoto_board_html:jobs_html(Jobs, Filters).

-doc "Binary page name (from a route binding) to its page atom.".
-spec page_atom(binary()) -> atom().
page_atom(~"overview") -> overview;
page_atom(~"queues") -> queues;
page_atom(~"workers") -> workers;
page_atom(~"jobs") -> jobs;
page_atom(~"batches") -> batches;
page_atom(~"cron") -> cron;
page_atom(~"failures") -> failures;
page_atom(~"dlq") -> dlq;
page_atom(_) -> overview.

%% ---------------------------------------------------------------------------
%% jobs filters <-> query string
%% ---------------------------------------------------------------------------

-doc "Parse the jobs filter/page state from a parsed query string.".
-spec filters_from_qs([{binary(), binary() | true}]) -> map().
filters_from_qs(Qs) ->
    #{
        filter_state => qs_val(~"state", Qs),
        filter_queue => qs_val(~"queue", Qs),
        filter_worker => qs_val(~"worker", Qs),
        page => qs_page(Qs)
    }.

search_map(Filters) ->
    Page = page_of(Filters),
    Base = #{limit => ?PAGE_SIZE, offset => (Page - 1) * ?PAGE_SIZE},
    with_filter(
        state,
        maps:get(filter_state, Filters, ~""),
        with_filter(
            queue,
            maps:get(filter_queue, Filters, ~""),
            with_filter(worker, maps:get(filter_worker, Filters, ~""), Base)
        )
    ).

with_filter(_Key, ~"", Map) -> Map;
with_filter(Key, Value, Map) -> Map#{Key => Value}.

qs_val(Key, Qs) ->
    case proplists:get_value(Key, Qs) of
        undefined -> ~"";
        true -> ~"";
        V -> V
    end.

qs_page(Qs) ->
    case proplists:get_value(~"page", Qs) of
        V when is_binary(V) ->
            try
                max(1, binary_to_integer(V))
            catch
                _:_ -> 1
            end;
        _ ->
            1
    end.

page_of(Filters) ->
    case maps:get(page, Filters, 1) of
        P when is_integer(P), P > 0 -> P;
        _ -> 1
    end.

%% ---------------------------------------------------------------------------
%% internal
%% ---------------------------------------------------------------------------

full(Active, StreamPath, Inner) ->
    Body = shigoto_board_html:page(Active, StreamPath, Inner),
    {status, 200, shigoto_board_html:csp_headers(), iolist_to_binary(Body)}.

stream_path(Page) ->
    <<(shigoto_board:prefix())/binary, "/sse/", Page/binary>>.

jobs_stream_path(Filters) ->
    <<(stream_path(~"jobs"))/binary, (filters_to_qs(Filters))/binary>>.

filters_to_qs(Filters) ->
    Pairs =
        qs_pair(~"state", bin_field(filter_state, Filters)) ++
            qs_pair(~"queue", bin_field(filter_queue, Filters)) ++
            qs_pair(~"worker", bin_field(filter_worker, Filters)) ++
            [<<"page=", (integer_to_binary(page_of(Filters)))/binary>>],
    <<"?", (join_bin(~"&", Pairs))/binary>>.

-spec join_bin(binary(), [binary()]) -> binary().
join_bin(_Sep, []) -> ~"";
join_bin(_Sep, [H]) -> H;
join_bin(Sep, [H | T]) -> <<H/binary, Sep/binary, (join_bin(Sep, T))/binary>>.

-spec qs_pair(binary(), binary()) -> [binary()].
qs_pair(_Key, ~"") ->
    [];
qs_pair(Key, Value) ->
    [<<Key/binary, "=", (uri_encode(Value))/binary>>].

-spec uri_encode(binary()) -> binary().
uri_encode(Bin) ->
    case unicode:characters_to_binary(uri_string:quote(Bin)) of
        B when is_binary(B) -> B;
        _ -> Bin
    end.

-spec bin_field(atom(), map()) -> binary().
bin_field(Key, Filters) ->
    case maps:get(Key, Filters, ~"") of
        V when is_binary(V) -> V;
        _ -> ~""
    end.

ok_list({ok, L}) when is_list(L) -> L;
ok_list(_) -> [].

ok_map({ok, M}) when is_map(M) -> M;
ok_map(_) -> #{}.
