-module(shigoto_board_ws).
-moduledoc """
WebSocket handler wrapping Arizona Nova WebSocket for live views.
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
    case arizona_nova_websocket:websocket_handle(Frame, State) of
        {reply, Frames, NewState} when is_list(Frames) ->
            case Frames of
                [Single] -> {reply, Single, NewState};
                [First | Rest] ->
                    lists:foreach(
                        fun(F) -> self() ! {pending_frame, F} end,
                        Rest
                    ),
                    {reply, First, NewState}
            end;
        Other ->
            Other
    end.

-doc false.
websocket_info({pending_frame, Frame}, State) ->
    {reply, Frame, State};
websocket_info(Msg, State) ->
    case arizona_nova_websocket:websocket_info(Msg, State) of
        {reply, Frames, NewState} when is_list(Frames) ->
            case Frames of
                [] -> {ok, NewState};
                [Single] -> {reply, Single, NewState};
                [First | Rest] ->
                    lists:foreach(
                        fun(F) -> self() ! {pending_frame, F} end,
                        Rest
                    ),
                    {reply, First, NewState}
            end;
        Other ->
            Other
    end.

-doc false.
terminate(Reason, Req, State) ->
    arizona_nova_websocket:terminate(Reason, Req, State).
