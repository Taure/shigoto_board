-module(shigoto_board_router).
-moduledoc """
Nova router for shigoto_board. Mounted via nova_apps config.
""".
-behaviour(nova_router).

-export([routes/1]).

-doc false.
routes(_Env) ->
    Prefix = shigoto_board:prefix(),
    AssetsPrefix = <<Prefix/binary, "/assets/[...]">>,
    #{
        prefix => <<>>,
        routes => [
            {<<"/">>, {shigoto_board_page_controller, index}, #{methods => [get]}},
            {<<"/:page">>, {shigoto_board_page_controller, index}, #{methods => [get]}},
            {<<"/live">>, shigoto_board_ws},
            {AssetsPrefix, cowboy_static, {priv_dir, shigoto_board, <<"static/assets">>}}
        ]
    }.
