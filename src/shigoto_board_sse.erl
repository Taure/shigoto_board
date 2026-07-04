-module(shigoto_board_sse).
-moduledoc """
The board's live transport: one long-lived SSE stream per open page.

`stream/1` is a normal Nova controller returning `{stream, Code, Headers,
Source}`. That tuple is picked up by a return-handler we register
(`handle_stream/3`), which `stream_reply`s the SSE headers and then **holds the
connection**, repainting the `#page` region every `refresh_ms` and never
returning - so Nova's buffered `render_response` (which would reply again and
crash) never runs. On client disconnect the next `stream_body` fails and the
request process exits. See novaframework/nova#387.

Per-connection state (the jobs filter/page) rides as query params on the stream
URL, so each viewer polls exactly the slice they are looking at. Both the first
paint and these live frames call `shigoto_board_page_controller:page_inner/2`,
so they always agree.
""".

-export([register/0, stream/1, handle_stream/3]).

-define(SELECTOR, ~"#page").

-spec register() -> ok | {error, atom()}.
register() ->
    nova_handlers:register_handler(stream, fun ?MODULE:handle_stream/3).

%% Nova controller: GET <prefix>/sse/:page
stream(Req) ->
    Page = maps:get(~"page", maps:get(bindings, Req, #{}), ~"overview"),
    Qs = cowboy_req:parse_qs(Req),
    {stream, 200, headers(), {Page, Qs}}.

handle_stream({stream, Code, Headers, {Page, Qs}}, _Callback, Req0) ->
    Req = cowboy_req:stream_reply(Code, Headers, Req0),
    loop_poll(page_atom(Page), page_opt(Page, Qs), Req).

loop_poll(Page, Opt, Req) ->
    receive
        _ -> loop_poll(Page, Opt, Req)
    after refresh() ->
        case send(Req, frame(Page, Opt)) of
            ok -> loop_poll(Page, Opt, Req);
            stop -> ok
        end
    end.

frame(Page, Opt) ->
    Inner = shigoto_board_page_controller:page_inner(Page, Opt),
    datastar:patch_elements(Inner, #{selector => ?SELECTOR, mode => inner}).

page_atom(Page) ->
    shigoto_board_page_controller:page_atom(Page).

page_opt(~"jobs", Qs) ->
    shigoto_board_page_controller:filters_from_qs(Qs);
page_opt(_Page, _Qs) ->
    undefined.

send(Req, Frame) ->
    try
        ok = cowboy_req:stream_body(Frame, nofin, Req),
        ok
    catch
        _:_ -> stop
    end.

headers() ->
    maps:from_list(datastar:sse_headers()).

refresh() ->
    shigoto_board:refresh_ms().
