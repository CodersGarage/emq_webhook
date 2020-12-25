%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% Define the default actions.
-module(emqx_web_hook_actions).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").

-define(RESOURCE_TYPE_WEBHOOK, 'web_hook').
-define(RESOURCE_CONFIG_SPEC, #{
            method => #{order => 1,
                        type => string,
                        enum => [<<"PUT">>,<<"POST">>,<<"GET">>,<<"DELETE">>],
                        default => <<"POST">>,
                        title => #{en => <<"Request Method">>,
                                   zh => <<"请求方法"/utf8>>},
                        description => #{en => <<"Request Method. \n"
                                                 "Note that: the Payload Template of Action will be discarded in case of GET method">>,
                                         zh => <<"请求方法。\n"
                                                 "注意：当方法为 GET 时，动作中的 '消息内容模板' 参数会被忽略"/utf8>>}},
            url => #{order => 2,
                     type => string,
                     format => url,
                     required => true,
                     title => #{en => <<"Request URL">>,
                                zh => <<"请求 URL"/utf8>>},
                     description => #{en => <<"Request URL">>,
                                      zh => <<"请求 URL"/utf8>>}},
            connect_timeout => #{order => 3,
                                  type => number,
                                  default => 5,
                                  title => #{en => <<"Connect Timeout">>,
                                             zh => <<"连接超时时间"/utf8>>},
                                  description => #{en => <<"Connect Timeout In Seconds">>,
                                                   zh => <<"连接超时时间，单位秒"/utf8>>}},
            request_timeout => #{order => 4,
                                 type => number,
                                 default => 5,
                                 title => #{en => <<"Request Timeout">>,
                                            zh => <<"请求超时时间时间"/utf8>>},
                                 description => #{en => <<"Request Timeout In Seconds">>,
                                                   zh => <<"请求超时时间，单位秒"/utf8>>}},
            pool_size => #{order => 5,
                           type => number,
                           default => 32,
                           title => #{en => <<"Pool Size">>,
                                      zh => <<"池大小"/utf8>>},
                           description => #{en => <<"Connection process pool size">>,
                                             zh => <<"连接进程池大小"/utf8>>}},
            content_type => #{order => 6,
                              type => string,
                              enum => [<<"application/json">>,<<"text/plain;charset=UTF-8">>],
                              default => <<"application/json">>,
                              title => #{en => <<"Content-Type">>,
                                         zh => <<"Content-Type"/utf8>>},
                              description => #{en => <<"The Content-Type of HTTP Request">>,
                                               zh => <<"HTTP 请求头中的 Content-Type 字段值"/utf8>>}},
            headers => #{order => 7,
                         type => object,
                         schema => #{},
                         default => #{},
                         title => #{en => <<"Request Header">>,
                                    zh => <<"请求头"/utf8>>},
                         description => #{en => <<"The custom HTTP request headers">>,
                                          zh => <<"自定义的 HTTP 请求头列表"/utf8>>}}
        }).

-define(ACTION_PARAM_RESOURCE, #{
            order => 0,
            type => string,
            required => true,
            title => #{en => <<"Resource ID">>,
                       zh => <<"资源 ID"/utf8>>},
            description => #{en => <<"Bind a resource to this action">>,
                             zh => <<"给动作绑定一个资源"/utf8>>}
        }).

-define(ACTION_DATA_SPEC, #{
            '$resource' => ?ACTION_PARAM_RESOURCE,
            path => #{order => 1,
                      type => string,
                      required => false,
                      default => <<>>,
                      title => #{en => <<"Path">>,
                                 zh => <<"Path"/utf8>>},
                      description => #{en => <<"A path component, variable interpolation from "
                                               "SQL statement is supported. This value will be "
                                               "concatenated with Request URL.">>,
                                       zh => <<"URL 的路径配置，支持使用 ${} 获取规则输出的字段值。\n"
                                               "例如：${clientid}。该值会与 Request URL 组成一个完整的 URL"/utf8>>}
                     },
            payload_tmpl => #{
                order => 2,
                type => string,
                input => textarea,
                required => false,
                default => <<"">>,
                title => #{en => <<"Payload Template">>,
                           zh => <<"消息内容模板"/utf8>>},
                description => #{en => <<"The payload template, variable interpolation is supported."
                                         "If using empty template (default), then the payload will "
                                         "be all the available vars in JSON format">>,
                                 zh => <<"消息内容模板，支持使用 ${} 获取变量值。"
                                         "默认消息内容为规则输出的所有字段的 JSON 字符串"/utf8>>}}
            }).

-resource_type(#{name => ?RESOURCE_TYPE_WEBHOOK,
                 create => on_resource_create,
                 status => on_get_resource_status,
                 destroy => on_resource_destroy,
                 params => ?RESOURCE_CONFIG_SPEC,
                 title => #{en => <<"WebHook">>,
                            zh => <<"WebHook"/utf8>>},
                 description => #{en => <<"WebHook">>,
                                  zh => <<"WebHook"/utf8>>}
                }).

-rule_action(#{name => data_to_webserver,
               category => data_forward,
               for => '$any',
               create => on_action_create_data_to_webserver,
               params => ?ACTION_DATA_SPEC,
               types => [?RESOURCE_TYPE_WEBHOOK],
               title => #{en => <<"Data to Web Server">>,
                          zh => <<"发送数据到 Web 服务"/utf8>>},
               description => #{en => <<"Forward Messages to Web Server">>,
                                zh => <<"将数据转发给 Web 服务"/utf8>>}
              }).

-type(action_fun() :: fun((Data :: map(), Envs :: map()) -> Result :: any())).

-type(url() :: binary()).

-export_type([action_fun/0]).

-export([ on_resource_create/2
        , on_get_resource_status/2
        , on_resource_destroy/2
        ]).

-export([ on_action_create_data_to_webserver/2
        ]).

%%------------------------------------------------------------------------------
%% Actions for web hook
%%------------------------------------------------------------------------------

-spec(on_resource_create(binary(), map()) -> map()).
on_resource_create(ResId, Conf) ->
    {ok, _} = application:ensure_all_started(ehttpc),
    Options = pool_opts(Conf),
    PoolName = pool_name(ResId),
    start_resource(ResId, PoolName, Options),
    Conf#{<<"pool">> => PoolName, options => Options}.

start_resource(ResId, PoolName, Options) ->
    case ehttpc_pool:start_pool(PoolName, Options) of
        {ok, _} ->
            ?LOG(info, "Initiated Resource ~p Successfully, ResId: ~p",
                 [?RESOURCE_TYPE_WEBHOOK, ResId]);
        {error, {already_started, _Pid}} ->
            on_resource_destroy(ResId, #{<<"pool">> => PoolName}),
            start_resource(ResId, PoolName, Options);
        {error, Reason} ->
            ?LOG(error, "Initiate Resource ~p failed, ResId: ~p, ~0p",
                 [?RESOURCE_TYPE_WEBHOOK, ResId, Reason]),
            error({{?RESOURCE_TYPE_WEBHOOK, ResId}, create_failed})
    end.

-spec(on_get_resource_status(binary(), map()) -> map()).
on_get_resource_status(ResId, #{<<"url">> := Url}) ->
    #{is_alive =>
        case emqx_rule_utils:http_connectivity(Url) of
            ok -> true;
            {error, Reason} ->
                ?LOG(error, "Connectivity Check for ~p failed, ResId: ~p, ~0p",
                     [?RESOURCE_TYPE_WEBHOOK, ResId, Reason]),
                false
        end}.

-spec(on_resource_destroy(binary(), map()) -> ok | {error, Reason::term()}).
on_resource_destroy(ResId, #{<<"pool">> := PoolName}) ->
    ?LOG(info, "Destroying Resource ~p, ResId: ~p", [?RESOURCE_TYPE_WEBHOOK, ResId]),
    case ehttpc_pool:stop_pool(PoolName) of
        ok ->
            ?LOG(info, "Destroyed Resource ~p Successfully, ResId: ~p", [?RESOURCE_TYPE_WEBHOOK, ResId]);
        {error, Reason} ->
            ?LOG(error, "Destroy Resource ~p failed, ResId: ~p, ~p", [?RESOURCE_TYPE_WEBHOOK, ResId, Reason]),
            error({{?RESOURCE_TYPE_WEBHOOK, ResId}, destroy_failed})
    end.

%% An action that forwards publish messages to a remote web server.
-spec(on_action_create_data_to_webserver(Id::binary(), #{url() := string()}) -> action_fun()).
on_action_create_data_to_webserver(_Id, Params) ->
    #{method := Method,
      path := Path,
      headers := Headers,
      content_type := ContentType,
      payload_tmpl := PayloadTmpl,
      request_timeout := RequestTimeout,
      pool := Pool} = parse_action_params(Params),
    NHeaders = [{<<"content-type">>, ContentType} | Headers],
    PayloadTks = emqx_rule_utils:preproc_tmpl(PayloadTmpl),
    PathTks = emqx_rule_utils:preproc_tmpl(Path),
    fun(Selected, _Envs = #{clientid := ClientId}) ->
        Body = format_msg(PayloadTks, Selected),
        NPath = emqx_rule_utils:proc_tmpl(PathTks, Selected),
        Req = create_req(Method, NPath, NHeaders, Body),
        case ehttpc:request(ehttpc_pool:pick_worker(Pool, ClientId), Method, Req, RequestTimeout) of
            {ok, _, _} ->
                ok;
            {ok, _, _, _} ->
                ok;
            {error, Reason} ->
                ?LOG(error, "[WebHook Action] HTTP request error: ~p", [Reason])
        end
    end.

format_msg([], Data) ->
    emqx_json:encode(Data);
format_msg(Tokens, Data) ->
     emqx_rule_utils:proc_tmpl(Tokens, Data).

%%------------------------------------------------------------------------------
%% Internal functions
%%------------------------------------------------------------------------------

create_req(Method, Path, Headers, _Body)
  when Method =:= get orelse Method =:= delete ->
    {Path, Headers};
create_req(_, Path, Headers, Body) ->
  {Path, Headers, Body}.

parse_action_params(Params = #{<<"url">> := URL}) ->
    try
        #{path := CommonPath} = uri_string:parse(add_default_scheme(URL)),
        #{method => method(maps:get(<<"method">>, Params, <<"POST">>)),
          path => path(filename:join(CommonPath, maps:get(<<"path">>, Params, <<>>))),
          headers => headers(maps:get(<<"headers">>, Params, undefined)),
          content_type => maps:get(<<"content_type">>, Params, <<"application/json">>),
          payload_tmpl => maps:get(<<"payload_tmpl">>, Params, <<>>),
          request_timeout => timer:seconds(maps:get(<<"request_timeout">>, Params, 5)),
          pool => maps:get(<<"pool">>, Params)}
    catch _:_ ->
        throw({invalid_params, Params})
    end.

path(<<>>) -> <<"/">>;
path(Path) -> Path.

method(GET) when GET == <<"GET">>; GET == <<"get">> -> get;
method(POST) when POST == <<"POST">>; POST == <<"post">> -> post;
method(PUT) when PUT == <<"PUT">>; PUT == <<"put">> -> put;
method(DEL) when DEL == <<"DELETE">>; DEL == <<"delete">> -> delete.

headers(undefined) -> [];
headers(Headers) when is_list(Headers) -> Headers;
headers(Headers) when is_map(Headers) ->
    maps:fold(fun(K, V, Acc) ->
            [{str(K), str(V)} | Acc]
        end, [], Headers).

str(Str) when is_list(Str) -> Str;
str(Atom) when is_atom(Atom) -> atom_to_list(Atom);
str(Bin) when is_binary(Bin) -> binary_to_list(Bin).

add_default_scheme(<<"http://", _/binary>> = URL) ->
    URL;
add_default_scheme(<<"https://", _/binary>> = URL) ->
    URL;
add_default_scheme(URL) ->
    <<"http://", URL/binary>>.

pool_opts(Params = #{<<"url">> := URL}) ->
    #{host := Host0,
      port := Port} = uri_string:parse(add_default_scheme(URL)),
    Host = get_addr(binary_to_list(Host0)),
    PoolSize = maps:get(<<"pool_size">>, Params, 32),
    ConnectTimeout = maps:get(<<"connect_timeout">>, Params, 5),
    TransportOpts = case tuple_size(Host) =:= 8 of
                        true -> [inet6];
                        false -> []
                    end,
    [{host, Host},
     {port, Port},
     {pool_size, PoolSize},
     {pool_type, hash},
     {connect_timeout, timer:seconds(ConnectTimeout)},
     {retry, 5},
     {retry_timeout, 1000},
     {transport_opts, TransportOpts}].

get_addr(Hostname) ->
    case inet:parse_address(Hostname) of
        {ok, {_,_,_,_} = Addr} -> Addr;
        {ok, {_,_,_,_,_,_,_,_} = Addr} -> Addr;
        {error, einval} ->
            case inet:getaddr(Hostname, inet) of
                 {error, _} ->
                     {ok, Addr} = inet:getaddr(Hostname, inet6),
                     Addr;
                 {ok, Addr} -> Addr
            end
    end.

pool_name(ResId) ->
    list_to_atom("webhook:" ++ str(ResId)).