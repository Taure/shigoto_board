-module(shigoto_board_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    arizona_nova:register_views(shigoto_board, fun shigoto_board_controller:resolve_view/1),
    {ok, self()}.

stop(_State) ->
    ok.
