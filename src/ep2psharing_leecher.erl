%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(ep2psharing_leecher).

-behaviour(gen_server).

-export([start_link/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3,
         request_piece_block/4]).

-import(ep2psharing_utils, [take_random_elem/1]).

-include("ep2psharing_messaging.hrl").

-define(LEECHER_NAME, leecher).
-define(N_RAREST_PIECES, 10).
-define(ZERO_BLOCK_COUNT, 0).

-record(peer_connection,
        {state :: requested | handshaked,
         peer_id :: gen_server:server_ref(),
         socket :: socket()}).
-record(state,
        {metainfo :: #metainfo{},
         tracker_req_interval :: integer(),
         peer_connections :: #{gen_server:server_ref() => #peer_connection{}},
         pieces_presence :: array:array(boolean()),
         pieces_seeders ::
             array:array({interested, peer_set()} |
                         {requested, peer_set()} |
                         undefined |
                         uninterested),
         distributed_file :: file:io_device(),
         piece_request_worker_pool :: pid()}).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link(DownloadRequest, ExistingPieces, File) ->
    gen_server:start_link(?MODULE, [DownloadRequest, ExistingPieces, File], []).

init([DownloadRequest, ExistingPieces, File]) ->
    self() ! {tracker_request, DownloadRequest, ExistingPieces, File},
    {ok, #state{}}.

handle_call({block_request,
             #block_request{index = PieceIndex,
                            offset = PieceOffset,
                            length = BlockLen}},
            From,
            State =
                #state{distributed_file = File,
                       metainfo = #metainfo{info = #metainfo_info_field{piece_len = PieceLen}}}) ->
    spawn(fun() ->
             FileOffsetToPiece = PieceIndex * PieceLen,
             {ok, Block} =
                 file:pread(File,
                            FileOffsetToPiece + PieceOffset,
                            min(BlockLen, PieceLen - PieceOffset)),
             gen_server:reply(From,
                              {block_reply,
                               #block_reply{index = PieceIndex,
                                            offset = PieceOffset,
                                            block = Block}})
          end),
    {noreply, State};
handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast({handshake,
             #handshake{info_hash = InfoHash,
                        peer_id = InitiatorRef,
                        socket = InitiatorSocket,
                        have = ExistingPieces}},
            State = #state{peer_connections = PeerConnections, pieces_seeders = PiecesSeeders}) ->
    Connection =
        #peer_connection{state = handshaked,
                         peer_id = InitiatorRef,
                         socket = InitiatorSocket},
    NewPeerConnections = maps:update(InitiatorRef, Connection, PeerConnections),
    NewPiecesSeeders =
        add_seeder_pieces(InitiatorRef, PiecesSeeders, sets:to_list(ExistingPieces)),
    gen_server:cast(InitiatorRef,
                    {reciprocal_handshake,
                     #handshake{info_hash = InfoHash,
                                peer_id = {peer, node()},
                                socket = {self(), node()}}}),
    {noreply,
     State#state{peer_connections = NewPeerConnections, pieces_seeders = NewPiecesSeeders}};
handle_cast({reciprocal_handshake,
             #handshake{peer_id = RespondentId,
                        socket = RespondentSocket,
                        have = ExistingPieces}},
            State = #state{peer_connections = PeerConnections, pieces_seeders = PiecesSeeders}) ->
    case maps:get(RespondentId, PeerConnections) of
        {badkey, _} ->
            {noreply, State};
        Connection ->
            HandshakedConnection =
                Connection#peer_connection{state = handshaked, socket = RespondentSocket},
            NewPeerConnections = maps:update(RespondentId, HandshakedConnection, PeerConnections),
            NewPiecesSeeders =
                add_seeder_pieces(RespondentId, PiecesSeeders, sets:to_list(ExistingPieces)),
            {noreply,
             State#state{peer_connections = NewPeerConnections, pieces_seeders = NewPiecesSeeders}}
    end;
handle_cast({reciprocal_handshake, _Handshake}, State) ->
    {noreply, State};
handle_cast({have_piece, #have_piece{peer_id = PeerId, index = PieceIndex}},
            State = #state{pieces_seeders = PiecesSeeders}) ->
    NewPiecesSeeders = add_piece_seeder(PeerId, PieceIndex, PiecesSeeders),
    {noreply, State#state{pieces_seeders = NewPiecesSeeders}};
handle_cast(_Request, State = #state{}) ->
    {noreply, State}.

handle_info({tracker_request,
             #download_request{metainfo = MetaInfo},
             ExistingPieces,
             File},
            State) ->
    #metainfo{announce = AnnounceRef, info = #metainfo_info_field{pieces = PieceHashes}} =
        MetaInfo,
    AnnounceRequest = prepare_announce_request(MetaInfo, ExistingPieces),
    Reply = gen_server:call(AnnounceRef, {announce, AnnounceRequest}),
    io:write(Reply),
    case Reply of
        #announce_reply{failure = none,
                        interval = Interval,
                        peers = Peers} ->
            PiecesPresenceArray =
                existing_pieces_to_piece_presence_array(length(PieceHashes), ExistingPieces),
            send_handshake_to_peers(MetaInfo, Peers, ExistingPieces),
            PeerConnections = create_requested_peer_connections(Peers),
            self() ! leech_process,
            {noreply,
             State#state{peer_connections = PeerConnections,
                         metainfo = MetaInfo,
                         tracker_req_interval = Interval,
                         pieces_presence = PiecesPresenceArray,
                         pieces_seeders = init_pieces_seeders_array(PiecesPresenceArray),
                         distributed_file = File,
                         piece_request_worker_pool =
                             wpool:start(request_workers,
                                         [{workers, ?MAX_SIMULTANEOUS_PIECE_REQUESTS}])}};
        #announce_reply{failure = _Reason} ->
            todo
    end;
handle_info(leech_process,
            State =
                #state{pieces_seeders = PiecesSeeders,
                       distributed_file = File,
                       metainfo =
                           MetaInfo =
                               #metainfo{info =
                                             #metainfo_info_field{piece_len = PieceLen,
                                                                  name = FileName}}}) ->
    SortedByRarestPiece =
        lists:sort(fun({_, Left}, {_, Right}) -> rarest_piece_sorting_func(Left, Right) end,
                   lists:enumerate(
                       array:to_list(PiecesSeeders))),
    case lists:nth(1, SortedByRarestPiece) of
        uninterested ->
            io:fwrite("File ~s successfully downloaded!", [FileName]),
            {noreply, State};
        undefined ->
            io:fwrite("No suitable peers right now for later downloading"),
            {noreply, State};
        {requested, _} ->
            erlang:send_after(500, self(), leech_process),
            {noreply, State};
        {interested, _} ->
            %%    Take random of ?N_RAREST_PIECES, so peers don't request the same most rarest piece
            FirstRarestPieces =
                lists:filter(fun(Elem) ->
                                case Elem of
                                    {interested, _} ->
                                        true;
                                    _ ->
                                        false
                                end
                             end,
                             lists:sublist(SortedByRarestPiece, ?N_RAREST_PIECES)),
            {PieceIndex, {interested, PeerSet}} = take_random_elem(FirstRarestPieces),
            RandomPeer = take_random_elem(PeerSet),
            NewPiecesSeeders = array:set(PieceIndex - 1, {requested, PeerSet}, PiecesSeeders),
            LeecherPid = self(),
            spawn(fun() ->
                     %%      Block offsets of piece
                     {FileOffsetToPiece, FileOffsetToNextPiece} =
                         {(PieceIndex - 1) * PieceLen, PieceIndex * PieceLen},
                     BlockOffsets =
                         lists:seq(FileOffsetToPiece, FileOffsetToNextPiece, ?BLOCK_SIZE),
                     BlockLengths =
                         lists:map(fun(Offset) -> min(?BLOCK_SIZE, FileOffsetToNextPiece - Offset)
                                   end,
                                   BlockOffsets),
                     BlockAggregatorPid =
                         spawn(fun() ->
                                  block_aggregator(File,
                                                   PieceIndex - 1,
                                                   LeecherPid,
                                                   MetaInfo,
                                                   length(BlockLengths),
                                                   ?ZERO_BLOCK_COUNT)
                               end),
                     lists:foreach(fun({Offset, Len}) ->
                                      BlockRequest =
                                          #block_request{index = PieceIndex - 1,
                                                         offset = Offset,
                                                         length = Len},
                                      wpool:send_request(request_workers,
                                                         {ep2psharing_leecher,
                                                          request_piece_block,
                                                          [RandomPeer,
                                                           BlockRequest,
                                                           BlockAggregatorPid,
                                                           State]},
                                                         available_worker,
                                                         ?POOL_OCCUPATION_TIMEOUT)
                                   end,
                                   lists:zip(BlockOffsets, BlockLengths))
                  end),
            self() ! leech_process,
            {noreply, State#state{pieces_seeders = NewPiecesSeeders}}
    end;
handle_info({all_blocks_received, ZeroBasedPieceIndex},
            State =
                #state{pieces_presence = PiecesPresenceArray,
                       pieces_seeders = PiecesSeeders,
                       peer_connections = ConnectionMap}) ->
    NewPiecesPresence = array:set(ZeroBasedPieceIndex, true, PiecesPresenceArray),
    NewPiecesSeeders = array:set(ZeroBasedPieceIndex, uninterested, PiecesSeeders),
    send_have_to_peers(ConnectionMap, ZeroBasedPieceIndex),
    {noreply,
     State#state{pieces_presence = NewPiecesPresence, pieces_seeders = NewPiecesSeeders}};
handle_info({block_request_timeout, #block_request{index = PieceIndex}},
            State = #state{pieces_seeders = PiecesSeeders}) ->
    {requested, PeerSet} = array:get(PieceIndex, PiecesSeeders),
    NewPiecesSeeders = array:set(PieceIndex, {interested, PeerSet}, PiecesSeeders),
    {noreply, State#state{pieces_seeders = NewPiecesSeeders}};
%% TODO need to ban inaccessible peers
handle_info({block_request_failed, #block_request{index = PieceIndex}, _Reason},
            State = #state{pieces_seeders = PiecesSeeders}) ->
    {requested, PeerSet} = array:get(PieceIndex, PiecesSeeders),
    NewPiecesSeeders = array:set(PieceIndex, {interested, PeerSet}, PiecesSeeders),
    {noreply, State#state{pieces_seeders = NewPiecesSeeders}};
handle_info(receive_some_block_timeout, _State) ->
    {error,
     {receove_some_block_timeout,
      "Block aggregator haven't received messages for a long time"}};
handle_info(_Info, State = #state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #state{}) ->
    ok.

code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

request_piece_block(PeerId,
                    BlockRequest,
                    BlockAggregatorPid,
                    #state{peer_connections = PeerConnections}) ->
    #peer_connection{socket = Socket} = maps:get(PeerId, PeerConnections),
    case gen_server:call(Socket, {block_request, BlockRequest}, ?REQUEST_TIMEOUT) of
        {block_reply, BlockReply} ->
            BlockAggregatorPid ! {block_reply, BlockReply};
        {timeout, _Location} ->
            BlockAggregatorPid ! {block_request_timeout, BlockRequest};
        {Reason, _Location} ->
            BlockAggregatorPid ! {block_request_failed, BlockRequest, Reason}
    end.

block_aggregator(_File,
                 ZeroBasedPieceIndex,
                 LeecherPid,
                 _MetaInfo,
                 TotalBlocks,
                 BlockReceivedCount)
    when BlockReceivedCount == TotalBlocks ->
    LeecherPid ! {all_blocks_received, ZeroBasedPieceIndex};
block_aggregator(File,
                 ZeroBasedPieceIndex,
                 LeecherPid,
                 MetaInfo = #metainfo{info = #metainfo_info_field{piece_len = PieceLen}},
                 TotalBlocks,
                 BlockReceivedCount) ->
    receive
        {block_reply, #block_reply{offset = PieceOffset, block = Block}} ->
            ok = file:pwrite(File, ZeroBasedPieceIndex * PieceLen + PieceOffset, Block),
            block_aggregator(File,
                             ZeroBasedPieceIndex,
                             LeecherPid,
                             MetaInfo,
                             TotalBlocks,
                             BlockReceivedCount + 1);
        {block_request_timeout, BlockRequest} ->
            LeecherPid ! {block_request_timeout, BlockRequest};
        {block_request_failed, Reason} ->
            LeecherPid ! {block_request_failed, Reason}
    after (?POOL_OCCUPATION_TIMEOUT + ?REQUEST_TIMEOUT) * 2 ->
        LeecherPid ! receive_some_block_timeout
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

prepare_announce_request(#metainfo{info = InfoField}, ExistingPieces) ->
    InfoHash = ep2psharing_bencoding:calc_info_field_hash(InfoField),
    PeerRef = {peer, node()},
    #announce_request{info_hash = InfoHash,
                      node_id = PeerRef,
                      event = started,
                      downloaded = sets:size(ExistingPieces)}.

send_handshake_to_peers(#metainfo{info_hash = InfoHash}, Peers, ExistingPieces) ->
    lists:foreach(fun(Peer) ->
                     gen_server:cast(Peer,
                                     {handshake,
                                      #handshake{info_hash = InfoHash,
                                                 peer_id = {peer, node()},
                                                 socket = {self(), node()},
                                                 have = ExistingPieces}})
                  end,
                  Peers).

send_have_to_peers(PeerConnectionMap, PieceIndex) ->
    HandshakedConnections =
        lists:filter(fun(#peer_connection{socket = Socket}) -> not Socket == unhandshaked end,
                     maps:values(PeerConnectionMap)),
    HavePieceMessage = #have_piece{peer_id = {peer, node()}, index = PieceIndex},
    lists:foreach(fun(#peer_connection{socket = Socket}) ->
                     gen_server:cast(Socket, {have_piece, HavePieceMessage})
                  end,
                  HandshakedConnections).

create_requested_peer_connections(Peers) ->
    Entries =
        lists:map(fun(PeerRef) ->
                     {PeerRef,
                      #peer_connection{state = requested,
                                       peer_id = PeerRef,
                                       socket = not_handshaked}}
                  end,
                  sets:to_list(Peers)),
    maps:from_list(Entries).

existing_pieces_to_piece_presence_array(NumberOfPieces, ExistingPieces) ->
    array:map(fun(Index, _Elem) -> sets:is_element(Index + 1, ExistingPieces) end,
              array:new(NumberOfPieces)).

init_pieces_seeders_array(PresenceArray) ->
    array:map(fun(_Index, Elem) ->
                 case Elem of
                     true ->
                         uninterested;
                     _ ->
                         undefined
                 end
              end,
              PresenceArray).

add_seeder_pieces(_PeerId, PiecesSeeders, []) ->
    PiecesSeeders;
add_seeder_pieces(PeerId, PiecesSeeders, [ExistingPieceIndex | Rest]) ->
    add_seeder_pieces(PeerId,
                      add_piece_seeder(PeerId, ExistingPieceIndex, PiecesSeeders),
                      Rest).

add_piece_seeder(PeerId, PieceIndex, PiecesSeeders) ->
    SeederSet = array:get(PieceIndex - 1, PiecesSeeders),
    NewSeederSet =
        case SeederSet of
            {interested, Set} ->
                sets:add_element(PeerId, Set);
            {requested, Set} ->
                sets:add_element(PeerId, Set);
            undefined ->
                {interested, sets:from_list([PeerId])};
            Any ->
                Any
        end,
    array:set(PieceIndex - 1, NewSeederSet, {interested, PiecesSeeders}).

%% Order of terms: interested < requested < undefined < uninterested
%% So, if the first element in sorted array is uninterested -> we have all pieces
%% if undefined - we don't have suitable peers to download remaining piece(-s)
rarest_piece_sorting_func(_Left, uninterested) ->
    true;
rarest_piece_sorting_func(uninterested, _Right) ->
    false;
rarest_piece_sorting_func(_Left, undefined) ->
    true;
rarest_piece_sorting_func(undefined, _Right) ->
    false;
rarest_piece_sorting_func(_Left, {requested, _}) ->
    true;
rarest_piece_sorting_func({requested, _}, _Right) ->
    false;
rarest_piece_sorting_func({interested, LeftVal}, {interested, RightVal}) ->
    LeftVal < RightVal.
