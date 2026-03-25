-module(shigoto_board).

-export([prefix/0]).

-spec prefix() -> binary().
prefix() ->
    case application:get_env(shigoto_board, prefix, ~"/shigoto") of
        Prefix when is_binary(Prefix) -> Prefix;
        Prefix when is_list(Prefix) -> list_to_binary(Prefix)
    end.
