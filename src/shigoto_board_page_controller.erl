-module(shigoto_board_page_controller).
-moduledoc """
HTTP handler for shigoto_board pages. Serves initial HTML with
Arizona LiveView bootstrapping.
""".

-export([index/1]).

-doc false.
index(Req) ->
    Path = cowboy_req:path(Req),
    Page = page_from_path(Path),
    View = resolve_view(Page),
    ArizonaReq = arizona_nova:cowboy_req_to_arizona_req(Req),
    {ok, Mounted} = arizona_view:call_mount_callback(View, undefined, ArizonaReq),
    {ok, Html} = arizona_renderer:render_layout(Mounted),
    {status, 200, #{<<"content-type">> => <<"text/html; charset=utf-8">>}, Html}.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

page_from_path(Path) ->
    Prefix = shigoto_board:prefix(),
    PrefixSize = byte_size(Prefix),
    case Path of
        <<Prefix:PrefixSize/binary>> -> <<"overview">>;
        <<Prefix:PrefixSize/binary, "/">> -> <<"overview">>;
        <<Prefix:PrefixSize/binary, "/", Rest/binary>> -> Rest;
        _ -> <<"overview">>
    end.

resolve_view(<<"overview">>) -> shigoto_board_overview_view;
resolve_view(<<"queues">>) -> shigoto_board_queues_view;
resolve_view(<<"workers">>) -> shigoto_board_workers_view;
resolve_view(<<"jobs">>) -> shigoto_board_jobs_view;
resolve_view(<<"batches">>) -> shigoto_board_batches_view;
resolve_view(<<"failures">>) -> shigoto_board_failures_view;
resolve_view(_) -> shigoto_board_overview_view.
