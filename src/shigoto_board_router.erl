-module(shigoto_board_router).
-behaviour(nova_router).

-export([routes/1]).

routes(_Env) ->
    [
        #{
            prefix => shigoto_board:prefix(),
            security => false,
            routes => [
                {~"/", fun shigoto_board_controller:index/1, #{methods => [get]}},
                {~"/:page", fun shigoto_board_controller:index/1, #{methods => [get]}},
                {"/assets/[...]", "static/assets"}
            ]
        }
    ].
