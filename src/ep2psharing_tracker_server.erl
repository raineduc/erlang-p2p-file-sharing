%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. янв. 2023 17:42
%%%-------------------------------------------------------------------
-module(ep2psharing_tracker_server).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-type info_hash() :: string().

-type peer_set() :: list(gen_server:server_ref()).

-define(DEFAULT_INTERVAL, 5).

-record(announce_request, {
  info_hash :: info_hash(),
  node_id :: gen_server:server_ref(),
  event :: started | completed | stopped | empty,
  downloaded :: integer(),
  uploaded :: integer()
}).

-record(announce_reply, {
  failure :: string() | none,
  interval :: integer(),
  peers :: peer_set()
}).

-record(state, {
  torrents :: #{info_hash() => peer_set()}
}).


start_link() ->
  gen_server:start_link({global, tracker_server}, tracker_server, [], []).

init(_Args) ->
  {ok, #state{}}.

handle_call({announce, #announce_request{ info_hash = InfoHash, node_id = NodeId }}, _From, #state{torrents = Torrents}) ->
  Peers = maps:get(InfoHash, Torrents, sets:new()),
  NewPeers = sets:add_element(NodeId, Peers),
  NewTorrents = maps:update(InfoHash, NewPeers, Torrents),
  Reply = #announce_reply{ failure = none, interval = ?DEFAULT_INTERVAL, peers = Peers },
  {reply, Reply, #state{ torrents = NewTorrents }}.

handle_cast(_, State) ->
  {noreply, State}.