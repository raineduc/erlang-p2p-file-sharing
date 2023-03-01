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

-include("ep2psharing_messaging.hrl").

%% API
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(DEFAULT_INTERVAL, 5).

-record(state, {peers_by_info_hash :: #{info_hash() => peer_set()}}).

start_link() ->
    gen_server:start_link({local, tracker_server}, ?MODULE, [], []).

init(_Args) ->
    {ok, #state{peers_by_info_hash = maps:new()}}.

handle_call({announce, #announce_request{info_hash = InfoHash, node_id = NodeId}},
            _From,
            #state{peers_by_info_hash = PeerMap}) ->
    Peers = maps:get(InfoHash, PeerMap, sets:new()),
    NewPeers = sets:add_element(NodeId, Peers),
    NewPeerMap = maps:put(InfoHash, NewPeers, PeerMap),
    Reply =
        #announce_reply{failure = none,
                        interval = ?DEFAULT_INTERVAL,
                        peers = sets:del_element(NodeId, Peers)},
    {reply, Reply, #state{peers_by_info_hash = NewPeerMap}}.

handle_cast(_, State) ->
    {noreply, State}.
