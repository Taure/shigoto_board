-module(shigoto_board).
-moduledoc """
Live dashboard for Shigoto background jobs.

Mount as a Nova app:

```erlang
%% sys.config
{my_app, [
    {nova_apps, [
        {shigoto_board, #{prefix => \"/jobs\"}}
    ]}
]},
{shigoto_board, [
    {prefix, \"/jobs\"}
]}
```
""".

-export([prefix/0]).

-doc "Get the configured mount prefix. Default: `/jobs`.".
-spec prefix() -> binary().
prefix() ->
    application:get_env(shigoto_board, prefix, <<"/jobs">>).
