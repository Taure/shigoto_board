-module(shigoto_board_cron_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1]).

mount(_Arg, _Req) ->
    Entries = shigoto_config:cron_entries(),
    Prefix = shigoto_board:prefix(),
    Bindings = #{id => ~"cron_view", entries => Entries},
    Layout = {shigoto_board_layout, render, main_content, #{
        active_page => ~"cron", prefix => Prefix, ws_path => <<(arizona_nova:prefix())/binary, "/live">>, arizona_prefix => arizona_nova:prefix()
    }},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Entries = arizona_template:get_binding(entries, Bindings),
    case Entries of
        [] -> render_empty(Bindings);
        _ -> render_with_entries(Bindings, Entries)
    end.

render_empty(Bindings) ->
    arizona_template:from_html(~"""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <div class="card">
            <div class="card-title">Cron Entries</div>
            <p class="empty">No cron entries configured</p>
        </div>
    </div>
    """).

render_with_entries(Bindings, Entries) ->
    arizona_template:from_html(
        ~""""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <div class="card">
            <div class="card-title">Cron Entries</div>
            <table>
                <thead><tr><th>Name</th><th>Schedule</th><th>Worker</th></tr></thead>
                <tbody>
                    {arizona_template:render_list(fun({Name, Schedule, Worker, _Args}) ->
                        arizona_template:from_html(~"""
                        <tr>
                            <td>{fmt(Name)}</td>
                            <td class="mono">{Schedule}</td>
                            <td class="mono">{atom_to_binary(Worker)}</td>
                        </tr>
                        """)
                    end, Entries)}
                </tbody>
            </table>
        </div>
    </div>
    """"
    ).

fmt(V) when is_atom(V) -> atom_to_binary(V);
fmt(V) when is_binary(V) -> V;
fmt(V) -> iolist_to_binary(io_lib:format(~"~p", [V])).
