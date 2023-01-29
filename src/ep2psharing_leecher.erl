%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(ep2psharing_leecher).

-behaviour(gen_server).

-export([start_link/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-include("ep2psharing_messaging.hrl").

-define(LEECHER_NAME, leecher).

-record(state, {}).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link(DownloadRequest, ExistingPieces, File) ->
    gen_server:start_link(?MODULE, [DownloadRequest, ExistingPieces, File], []).

init([DownloadRequest, ExistingPieces, File]) ->
    self() ! {tracker_request, DownloadRequest, ExistingPieces, File},
    {ok, #state{}}.

handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast(_Request, State = #state{}) ->
    {noreply, State}.

handle_info({tracker_request,
             #download_request{metainfo = MetaInfo},
             ExistingPieces,
             _File},
            State) ->
    #metainfo{announce = AnnounceRef} = MetaInfo,
    AnnounceRequest = prepare_announce_request(MetaInfo, ExistingPieces),
    Reply = gen_server:call(AnnounceRef, {announce, AnnounceRequest}),
    io:write(Reply),
    {noreply, State};
handle_info(_Info, State = #state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #state{}) ->
    ok.

code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

prepare_announce_request(#metainfo{info = InfoField}, ExistingPieces) ->
    BencodedInfo = ep2psharing_bencoding:encode_info_field(InfoField),
    InfoHash = binary_to_list(crypto:hash(sha, BencodedInfo)),
    SelfRef = {?LEECHER_NAME, node()},
    #announce_request{info_hash = InfoHash,
                      node_id = SelfRef,
                      event = started,
                      downloaded = sets:size(ExistingPieces)}.
