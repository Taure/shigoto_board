-module(shigoto_board).

-export([prefix/0, refresh_ms/0]).

-spec prefix() -> binary().
prefix() ->
    to_bin(application:get_env(shigoto_board, prefix, ~"/shigoto")).

-spec refresh_ms() -> pos_integer().
refresh_ms() ->
    case application:get_env(shigoto_board, refresh_ms, 2000) of
        N when is_integer(N), N > 0 -> N;
        _ -> 2000
    end.

-spec to_bin(term()) -> binary().
to_bin(V) when is_binary(V) ->
    V;
to_bin(V) when is_list(V) ->
    <<<<C:8>> || C <- V, is_integer(C)>>;
to_bin(_) ->
    ~"/shigoto".
