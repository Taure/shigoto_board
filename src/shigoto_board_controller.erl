-module(shigoto_board_controller).

-export([index/1, resolve_view/1]).

-spec index(Req :: map()) -> {status, integer(), map(), iodata()}.
index(CowboyReq) ->
    Path = cowboy_req:path(CowboyReq),
    {ViewModule, MountArg} = resolve_view_module(Path),
    ArizonaReq = arizona_cowboy_request:new(CowboyReq),
    try
        View = arizona_view:call_mount_callback(ViewModule, MountArg, ArizonaReq),
        {Html, _RenderView} = arizona_renderer:render_layout(View),
        {status, 200, #{~"content-type" => ~"text/html; charset=utf-8"}, Html}
    catch
        Error:Reason:Stacktrace ->
            logger:error(~"Shigoto board render error: ~p:~p~n~p", [Error, Reason, Stacktrace]),
            {status, 500, #{~"content-type" => ~"text/html"}, ~"Internal Server Error"}
    end.

-spec resolve_view(map()) -> {view, module(), term(), list()}.
resolve_view(#{path := Path}) ->
    {ViewModule, MountArg} = resolve_view_module(Path),
    {view, ViewModule, MountArg, []}.

resolve_view_module(Path) ->
    case page_from_path(Path) of
        ~"queues" -> {shigoto_board_queues_view, undefined};
        ~"workers" -> {shigoto_board_workers_view, undefined};
        ~"jobs" -> {shigoto_board_jobs_view, undefined};
        ~"batches" -> {shigoto_board_batches_view, undefined};
        ~"cron" -> {shigoto_board_cron_view, undefined};
        _ -> {shigoto_board_overview_view, undefined}
    end.

page_from_path(Path) ->
    Pages = [~"queues", ~"workers", ~"jobs", ~"batches", ~"cron"],
    case binary:split(Path, ~"/", [global, trim_all]) of
        [] ->
            ~"overview";
        Parts ->
            Last = lists:last(Parts),
            case lists:member(Last, Pages) of
                true -> Last;
                false -> ~"overview"
            end
    end.
