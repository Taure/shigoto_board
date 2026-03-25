-module(shigoto_board_layout).
-compile({parse_transform, arizona_parse_transform}).

-export([render/1]).

render(Bindings) ->
    arizona_template:from_html(
        ~"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Shigoto Board</title>
        <link rel="stylesheet" href="{arizona_template:get_binding(prefix, Bindings)}/assets/css/shigoto_board.css" />
        <script type="module">
            import Arizona from '{arizona_template:get_binding(arizona_prefix, Bindings)}/assets/js/arizona.min.js';
            globalThis.arizona = new Arizona();
            arizona.connect('{arizona_template:get_binding(ws_path, Bindings)}');
        </script>
    </head>
    <body>
        <nav class="nav">
            <span class="nav-brand">Shigoto</span>
            <div class="nav-links">
                <a href="{arizona_template:get_binding(prefix, Bindings)}" class="{nav_class(arizona_template:get_binding(active_page, Bindings), ~"overview")}">Overview</a>
                <a href="{arizona_template:get_binding(prefix, Bindings)}/queues" class="{nav_class(arizona_template:get_binding(active_page, Bindings), ~"queues")}">Queues</a>
                <a href="{arizona_template:get_binding(prefix, Bindings)}/workers" class="{nav_class(arizona_template:get_binding(active_page, Bindings), ~"workers")}">Workers</a>
                <a href="{arizona_template:get_binding(prefix, Bindings)}/jobs" class="{nav_class(arizona_template:get_binding(active_page, Bindings), ~"jobs")}">Jobs</a>
                <a href="{arizona_template:get_binding(prefix, Bindings)}/batches" class="{nav_class(arizona_template:get_binding(active_page, Bindings), ~"batches")}">Batches</a>
                <a href="{arizona_template:get_binding(prefix, Bindings)}/cron" class="{nav_class(arizona_template:get_binding(active_page, Bindings), ~"cron")}">Cron</a>
            </div>
        </nav>
        <main class="main">
            {arizona_template:render_slot(arizona_template:get_binding(main_content, Bindings))}
        </main>
    </body>
    </html>
    """
    ).

nav_class(Active, Page) when Active =:= Page -> ~"active";
nav_class(_, _) -> ~"".
