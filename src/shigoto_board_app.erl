-module(shigoto_board_app).
-moduledoc """
Application entry point.

Registers the `{stream, ...}` Datastar SSE return-handler with Nova so the
per-page live regions can hold a connection open and repaint. The dashboard
carries no state of its own - each SSE connection polls Shigoto directly - so
there is no supervision tree to start.
""".
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ok = shigoto_board_sse:register(),
    {ok, self()}.

stop(_State) ->
    ok.
