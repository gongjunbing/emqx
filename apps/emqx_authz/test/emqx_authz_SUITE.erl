%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_authz_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include("emqx_authz.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-define(CONF_DEFAULT, <<"authorization: {sources: []}">>).

all() ->
    emqx_ct:all(?MODULE).

groups() ->
    [].

init_per_suite(Config) ->
    meck:new(emqx_schema, [non_strict, passthrough, no_history, no_link]),
    meck:expect(emqx_schema, fields, fun("authorization") ->
                                             meck:passthrough(["authorization"]) ++
                                             emqx_authz_schema:fields("authorization");
                                        (F) -> meck:passthrough([F])
                                     end),

    meck:new(emqx_resource, [non_strict, passthrough, no_history, no_link]),
    meck:expect(emqx_resource, create, fun(_, _, _) -> {ok, meck_data} end),
    meck:expect(emqx_resource, update, fun(_, _, _, _) -> {ok, meck_data} end),
    meck:expect(emqx_resource, remove, fun(_) -> ok end ),

    ok = emqx_config:init_load(emqx_authz_schema, ?CONF_DEFAULT),
    ok = emqx_ct_helpers:start_apps([emqx_authz]),
    {ok, _} = emqx:update_config([authorization, cache, enable], false),
    {ok, _} = emqx:update_config([authorization, no_match], deny),
    Config.

end_per_suite(_Config) ->
    {ok, _} = emqx_authz:update(replace, []),
    emqx_ct_helpers:stop_apps([emqx_authz, emqx_resource]),
    meck:unload(emqx_resource),
    meck:unload(emqx_schema),
    ok.

init_per_testcase(_, Config) ->
    {ok, _} = emqx_authz:update(replace, []),
    Config.

-define(SOURCE1, #{<<"type">> => <<"http">>,
                 <<"config">> => #{
                    <<"url">> => <<"https://fake.com:443/">>,
                    <<"headers">> => #{},
                    <<"method">> => <<"get">>,
                    <<"request_timeout">> => 5000}
                }).
-define(SOURCE2, #{<<"type">> => <<"mongo">>,
                 <<"config">> => #{
                        <<"mongo_type">> => <<"single">>,
                        <<"server">> => <<"127.0.0.1:27017">>,
                        <<"pool_size">> => 1,
                        <<"database">> => <<"mqtt">>,
                        <<"ssl">> => #{<<"enable">> => false}},
                 <<"collection">> => <<"fake">>,
                 <<"find">> => #{<<"a">> => <<"b">>}
                }).
-define(SOURCE3, #{<<"type">> => <<"mysql">>,
                 <<"config">> => #{
                     <<"server">> => <<"127.0.0.1:27017">>,
                     <<"pool_size">> => 1,
                     <<"database">> => <<"mqtt">>,
                     <<"username">> => <<"xx">>,
                     <<"password">> => <<"ee">>,
                     <<"auto_reconnect">> => true,
                     <<"ssl">> => #{<<"enable">> => false}},
                 <<"sql">> => <<"abcb">>
                }).
-define(SOURCE4, #{<<"type">> => <<"pgsql">>,
                 <<"config">> => #{
                     <<"server">> => <<"127.0.0.1:27017">>,
                     <<"pool_size">> => 1,
                     <<"database">> => <<"mqtt">>,
                     <<"username">> => <<"xx">>,
                     <<"password">> => <<"ee">>,
                     <<"auto_reconnect">> => true,
                     <<"ssl">> => #{<<"enable">> => false}},
                 <<"sql">> => <<"abcb">>
                }).
-define(SOURCE5, #{<<"type">> => <<"redis">>,
                 <<"config">> => #{
                     <<"server">> => <<"127.0.0.1:27017">>,
                     <<"pool_size">> => 1,
                     <<"database">> => 0,
                     <<"password">> => <<"ee">>,
                     <<"auto_reconnect">> => true,
                     <<"ssl">> => #{<<"enable">> => false}},
                 <<"cmd">> => <<"HGETALL mqtt_authz:%u">>
                }).

%%------------------------------------------------------------------------------
%% Testcases
%%------------------------------------------------------------------------------

t_update_source(_) ->
    {ok, _} = emqx_authz:update(replace, [?SOURCE2]),
    {ok, _} = emqx_authz:update(head, [?SOURCE1]),
    {ok, _} = emqx_authz:update(tail, [?SOURCE3]),

    ?assertMatch([#{type := http}, #{type := mongo}, #{type := mysql}], emqx:get_config([authorization, sources], [])),

    [#{annotations := #{id := Id1}, type := http},
     #{annotations := #{id := Id2}, type := mongo},
     #{annotations := #{id := Id3}, type := mysql}
    ] = emqx_authz:lookup(),

    {ok, _} = emqx_authz:update({replace_once, Id1}, ?SOURCE5),
    {ok, _} = emqx_authz:update({replace_once, Id3}, ?SOURCE4),
    ?assertMatch([#{type := redis}, #{type := mongo}, #{type := pgsql}], emqx:get_config([authorization, sources], [])),

    [#{annotations := #{id := Id1}, type := redis},
     #{annotations := #{id := Id2}, type := mongo},
     #{annotations := #{id := Id3}, type := pgsql}
    ] = emqx_authz:lookup(),

    {ok, _} = emqx_authz:update(replace, []).

t_move_source(_) ->
    {ok, _} = emqx_authz:update(replace, [?SOURCE1, ?SOURCE2, ?SOURCE3, ?SOURCE4, ?SOURCE5]),
    [#{annotations := #{id := Id1}},
     #{annotations := #{id := Id2}},
     #{annotations := #{id := Id3}},
     #{annotations := #{id := Id4}},
     #{annotations := #{id := Id5}}
    ] = emqx_authz:lookup(),

    {ok, _} = emqx_authz:move(Id4, <<"top">>),
    ?assertMatch([#{annotations := #{id := Id4}},
                  #{annotations := #{id := Id1}},
                  #{annotations := #{id := Id2}},
                  #{annotations := #{id := Id3}},
                  #{annotations := #{id := Id5}}
                 ], emqx_authz:lookup()),

    {ok, _} = emqx_authz:move(Id1, <<"bottom">>),
    ?assertMatch([#{annotations := #{id := Id4}},
                  #{annotations := #{id := Id2}},
                  #{annotations := #{id := Id3}},
                  #{annotations := #{id := Id5}},
                  #{annotations := #{id := Id1}}
                 ], emqx_authz:lookup()),

    {ok, _} = emqx_authz:move(Id3, #{<<"before">> => Id4}),
    ?assertMatch([#{annotations := #{id := Id3}},
                  #{annotations := #{id := Id4}},
                  #{annotations := #{id := Id2}},
                  #{annotations := #{id := Id5}},
                  #{annotations := #{id := Id1}}
                 ], emqx_authz:lookup()),

    {ok, _} = emqx_authz:move(Id2, #{<<"after">> => Id1}),
    ?assertMatch([#{annotations := #{id := Id3}},
                  #{annotations := #{id := Id4}},
                  #{annotations := #{id := Id5}},
                  #{annotations := #{id := Id1}},
                  #{annotations := #{id := Id2}}
                 ], emqx_authz:lookup()),
    ok.