-module(shigoto_board_layout).
-moduledoc """
Master HTML layout for shigoto_board pages.
""".

-export([render/1]).

-doc false.
render(Bindings) ->
    Prefix = shigoto_board:prefix(),
    Title = maps:get(title, Bindings, <<"Shigoto Board">>),
    Inner = maps:get(inner_content, Bindings, <<>>),
    ActivePage = maps:get(active_page, Bindings, <<"overview">>),
    iolist_to_binary([
        <<"<!DOCTYPE html><html lang=\"en\"><head>">>,
        <<"<meta charset=\"utf-8\">">>,
        <<"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">">>,
        <<"<title>">>,
        Title,
        <<"</title>">>,
        <<"<link rel=\"stylesheet\" href=\"">>,
        Prefix,
        <<"/assets/css/board.css\">">>,
        <<"</head><body>">>,
        <<"<nav class=\"board-nav\">">>,
        <<"<span class=\"board-logo\">&#x4ED5;&#x4E8B; Shigoto Board</span>">>,
        <<"<div class=\"board-links\">">>,
        nav_link(Prefix, <<"overview">>, <<"Overview">>, ActivePage),
        nav_link(Prefix, <<"queues">>, <<"Queues">>, ActivePage),
        nav_link(Prefix, <<"workers">>, <<"Workers">>, ActivePage),
        nav_link(Prefix, <<"jobs">>, <<"Jobs">>, ActivePage),
        nav_link(Prefix, <<"batches">>, <<"Batches">>, ActivePage),
        nav_link(Prefix, <<"failures">>, <<"Failures">>, ActivePage),
        <<"</div></nav>">>,
        <<"<main class=\"board-main\">">>,
        Inner,
        <<"</main>">>,
        <<"<script src=\"">>,
        Prefix,
        <<"/assets/js/arizona.min.js\"></script>">>,
        <<"<script>Arizona.connect(\"">>,
        Prefix,
        <<"/live\");</script>">>,
        <<"</body></html>">>
    ]).

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

nav_link(Prefix, Page, Label, ActivePage) ->
    Class =
        case Page of
            ActivePage -> <<"board-link active">>;
            _ -> <<"board-link">>
        end,
    Href =
        case Page of
            <<"overview">> -> Prefix;
            _ -> <<Prefix/binary, "/", Page/binary>>
        end,
    iolist_to_binary([
        <<"<a href=\"">>,
        Href,
        <<"\" class=\"">>,
        Class,
        <<"\">">>,
        Label,
        <<"</a>">>
    ]).
