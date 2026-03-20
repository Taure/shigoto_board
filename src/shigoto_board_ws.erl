-module(shigoto_board_ws).
-moduledoc """
WebSocket handler delegating to Arizona Nova WebSocket.
""".

-export([
    init/1,
    websocket_init/1,
    websocket_handle/2,
    websocket_info/2,
    terminate/3
]).

-doc false.
init(Req) ->
    arizona_nova_websocket:init(Req).

-doc false.
websocket_init(State) ->
    arizona_nova_websocket:websocket_init(State).

-doc false.
websocket_handle(Frame, State) ->
    arizona_nova_websocket:websocket_handle(Frame, State).

-doc false.
websocket_info(Msg, State) ->
    arizona_nova_websocket:websocket_info(Msg, State).

-doc false.
terminate(Reason, Req, State) ->
    arizona_nova_websocket:terminate(Reason, Req, State).
