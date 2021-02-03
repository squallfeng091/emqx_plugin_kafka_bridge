%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2016 Huang Rui<vowstar@gmail.com>, All Rights Reserved.
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------
%%% @doc
%%% emqttd_plugin_kafka_bridge.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(emqttd_plugin_kafka_bridge).


-include("../../emqx-4.2.0/include/emqx.hrl").

%%-include("../../../include/emqttd.hrl").
%%-include("../../../include/emqttd_protocol.hrl").
%%-include("../../../include/emqttd_internal.hrl").

-export([load/1, unload/0]).

%% Hooks functions
-export([on_client_connect/3
  , on_client_connected/3
  , on_client_disconnected/3
  , on_client_subscribe/4
  , on_client_unsubscribe/4]).

-export([on_client_subscribe_after/3]).

-export([on_message_publish/2, on_message_delivered/3, on_message_acked/3]).

-record(struct, {lst = []}).

%% Called when the plugin application start
load(Env) ->
  ekaf_init([Env]),
  emqx:hook('client.connect', {?MODULE, on_client_connect, [Env]}),
  emqx:hook('client.connack', {?MODULE, on_client_connack, [Env]}),
  emqx:hook('client.connected', {?MODULE, on_client_connected, [Env]}),
  emqx:hook('client.disconnected', {?MODULE, on_client_disconnected, [Env]}),
  emqx:hook('client.authenticate', {?MODULE, on_client_authenticate, [Env]}),
  emqx:hook('client.check_acl', {?MODULE, on_client_check_acl, [Env]}),
  emqx:hook('client.subscribe', {?MODULE, on_client_subscribe, [Env]}),
  emqx:hook('client.unsubscribe', {?MODULE, on_client_unsubscribe, [Env]}),
  emqx:hook('session.created', {?MODULE, on_session_created, [Env]}),
  emqx:hook('session.subscribed', {?MODULE, on_session_subscribed, [Env]}),
  emqx:hook('session.unsubscribed', {?MODULE, on_session_unsubscribed, [Env]}),
  emqx:hook('session.resumed', {?MODULE, on_session_resumed, [Env]}),
  emqx:hook('session.discarded', {?MODULE, on_session_discarded, [Env]}),
  emqx:hook('session.takeovered', {?MODULE, on_session_takeovered, [Env]}),
  emqx:hook('session.terminated', {?MODULE, on_session_terminated, [Env]}),
  emqx:hook('message.publish', {?MODULE, on_message_publish, [Env]}),
  emqx:hook('message.delivered', {?MODULE, on_message_delivered, [Env]}),
  emqx:hook('message.acked', {?MODULE, on_message_acked, [Env]}),
  emqx:hook('message.dropped', {?MODULE, on_message_dropped, [Env]}).


%%-----------client connect start-----------------------------------%%

on_client_connected(ClientInfo = #{clientid := ClientId}, ConnInfo, _Env) ->
  io:format("Client(~s) connected, ClientInfo:~n~p~n, ConnInfo:~n~p~n",
    [ClientId, ClientInfo, ConnInfo]),

  Json = mochijson2:encode([
    {type, <<"connected">>},
    {client_id, ClientId},
    {cluster_node, node()},
    {ts, emqttd_time:now_to_secs()}
  ]),

  ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json)),

  {ok, ClientInfo}.

on_client_connect(ConnInfo = #{clientid := ClientId}, Props, _Env) ->
  io:format("Client(~s) connect, ConnInfo: ~p, Props: ~p~n",
    [ClientId, ConnInfo, Props]),
  {ok, Props}.

%%-----------client connect end-------------------------------------%%


%%-----------client disconnect start---------------------------------%%

on_client_disconnected(ClientInfo = #{clientid := ClientId}, ReasonCode, ConnInfo, _Env) ->
  io:format("client ~s disconnected, reason: ~w~n", [ClientId, ReasonCode, ClientInfo, ConnInfo]),

  Json = mochijson2:encode([
    {type, <<"disconnected">>},
    {client_id, ClientId},
    {reason, ReasonCode},
    {cluster_node, node()},
    {ts, emqttd_time:now_to_secs()}
  ]),

  ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json)),

  ok.

%%-----------client disconnect end-----------------------------------%%


%%-----------client subscribed start---------------------------------------%%
%%on_client_subscribe(#{clientid := ClientId}, _Properties, TopicFilters, _Env) ->
%%  io:format("Client(~s) will subscribe: ~p~n", [ClientId, TopicFilters]),
%%  {ok, TopicFilters}.

%% should retain TopicTable
on_client_subscribe(#{clientid := ClientId}, _Properties, TopicTable, _Env) ->
  io:format("Client(~s) will subscribe: ~p~n", [ClientId, TopicTable]),

  case TopicTable of
    [_ | _] ->
      %% If TopicTable list is not empty
      Key = proplists:get_keys(TopicTable),
      %% build json to send using ClientId
      Json = mochijson2:encode([
        {type, <<"subscribed">>},
        {client_id, ClientId},
        {topic, lists:last(Key)},
        {cluster_node, node()},
        {ts, emqttd_time:now_to_secs()}
      ]),
      ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json));
    _ ->
      %% If TopicTable is empty
      io:format("empty topic ~n")
  end,

  {ok, TopicTable}.

%%-----------client subscribed end----------------------------------------%%


%%-----------client unsubscribed start----------------------------------------%%
%%on_client_unsubscribe(#{clientid := ClientId}, _Properties, TopicFilters, _Env) ->
%%  io:format("Client(~s) will unsubscribe ~p~n", [ClientId, TopicFilters]),
%%  {ok, TopicFilters}.

on_client_unsubscribe(#{clientid := ClientId}, _Properties, Topics, _Env) ->
  io:format("client ~s unsubscribe ~p~n", [ClientId, Topics]),

  % build json to send using ClientId
  Json = mochijson2:encode([
    {type, <<"unsubscribed">>},
    {client_id, ClientId},
    {topic, lists:last(Topics)},
    {cluster_node, node()},
    {ts, emqttd_time:now_to_secs()}
  ]),

  ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json)),

  {ok, Topics}.

%%-----------client unsubscribed end----------------------------------------%%


%%-----------message publish start--------------------------------------%%

%% transform message and return
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
  {ok, Message};

on_message_publish(Message, _Env) ->
  io:format("publish ~s~n", [emqx_message:format(Message)]),

  From = Message#message.from,
  Id = Message#message.id,
  Topic = Message#message.topic,
  Payload = Message#message.payload,
  QoS = Message#message.qos,
  Flags =Message#message.flags,
  Headers =Message#message.headers,
  Timestamp = Message#message.timestamp,

  Json = mochijson2:encode([
    {id, Id},
    {type, <<"published">>},
    {client_id, From},
    {topic, Topic},
    {payload, Payload},
    {qos, QoS},
    {flags,Flags},
    {headers,Flags}
    {cluster_node, node()},
    {ts, emqttd_time:now_to_secs(Timestamp)}
  ]),

  ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json)),

  {ok, Message}.

%%-----------message delivered start--------------------------------------%%
on_message_delivered(ClientId, Message, _Env) ->
  io:format("delivered to client ~s: ~s~n", [ClientId, emqttd_message:format(Message)]),

  From = Message#mqtt_message.from,
  Sender = Message#mqtt_message.sender,
  Topic = Message#mqtt_message.topic,
  Payload = Message#mqtt_message.payload,
  QoS = Message#mqtt_message.qos,
  Timestamp = Message#mqtt_message.timestamp,

  Json = mochijson2:encode([
    {type, <<"delivered">>},
    {client_id, ClientId},
    {from, From},
    {topic, Topic},
    {payload, Payload},
    {qos, QoS},
    {cluster_node, node()},
    {ts, emqttd_time:now_to_secs(Timestamp)}
  ]),

  ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json)),

  {ok, Message}.
%%-----------message delivered end----------------------------------------%%

%%-----------acknowledgement publish start----------------------------%%
on_message_acked(ClientId, Message, _Env) ->
  io:format("client ~s acked: ~s~n", [ClientId, emqttd_message:format(Message)]),

  From = Message#mqtt_message.from,
  Sender = Message#mqtt_message.sender,
  Topic = Message#mqtt_message.topic,
  Payload = Message#mqtt_message.payload,
  QoS = Message#mqtt_message.qos,
  Timestamp = Message#mqtt_message.timestamp,

  Json = mochijson2:encode([
    {type, <<"acked">>},
    {client_id, ClientId},
    {from, From},
    {topic, Topic},
    {payload, Payload},
    {qos, QoS},
    {cluster_node, node()},
    {ts, emqttd_time:now_to_secs(Timestamp)}
  ]),

  ekaf:produce_async_batched(<<"broker_message">>, list_to_binary(Json)),
  {ok, Message}.

%% ===================================================================
%% ekaf_init
%% ===================================================================

ekaf_init(_Env) ->
  %% Get parameters
  {ok, Kafka} = application:get_env(emqttd_plugin_kafka_bridge, kafka),
  BootstrapBroker = proplists:get_value(bootstrap_broker, Kafka),
  PartitionStrategy = proplists:get_value(partition_strategy, Kafka),
  %% Set partition strategy, like application:set_env(ekaf, ekaf_partition_strategy, strict_round_robin),
  application:set_env(ekaf, ekaf_partition_strategy, PartitionStrategy),
  %% Set broker url and port, like application:set_env(ekaf, ekaf_bootstrap_broker, {"127.0.0.1", 9092}),
  application:set_env(ekaf, ekaf_bootstrap_broker, BootstrapBroker),
  %% Set topic
  application:set_env(ekaf, ekaf_bootstrap_topics, <<"broker_message">>),

  {ok, _} = application:ensure_all_started(kafkamocker),
  {ok, _} = application:ensure_all_started(gproc),
  {ok, _} = application:ensure_all_started(ranch),
  {ok, _} = application:ensure_all_started(ekaf),

  io:format("Init ekaf with ~p~n", [BootstrapBroker]).


%% Called when the plugin application stop
unload() ->
  emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
  emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
  emqttd:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/3),
  emqttd:unhook('client.subscribe.after', fun ?MODULE:on_client_subscribe_after/3),
  emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/3),
  emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
  emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/3),
  emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/3).
