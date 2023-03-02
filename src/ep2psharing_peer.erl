-module(ep2psharing_peer).

-behaviour(gen_server).

-include("ep2psharing_messaging.hrl").

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([send_torrent_request/2]).

-record(torrent_info,
        {announce :: gen_server:server_ref(),
         metainfo :: #metainfo{},
         filename :: file:name_all(),
         existent_pieces :: sets:set(piece_index()),
         interval :: integer()}).
-record(state,
        {current_torrents :: #{info_hash() => #torrent_info{}},
         leecher_processes :: #{info_hash() => gen_server:server_ref()}}).

%%%===================================================================
%%% Public API
%%%===================================================================

%% @doc Отпраляет пиру запрос на скачивание/раздачу торрента, входная точка для начала всего процесса
%% по отдельному торренту
-spec send_torrent_request(gen_server:server_ref(), download_request()) ->
                              download_request().
send_torrent_request(SenderRef, DownloadRequest) ->
    peer ! {torrent, SenderRef, DownloadRequest}.

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
    gen_server:start_link({local, peer}, ?MODULE, [], []).

init(_Args) ->
    wpool:start(),
    {ok, #state{current_torrents = maps:new(), leecher_processes = maps:new()}}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast({handshake, Handshake = #handshake{info_hash = InfoHash}}, State) ->
    #handshake{info_hash = InfoHash} = Handshake,
    case maps:is_key(InfoHash, State#state.leecher_processes) of
        true ->
            gen_server:cast(
                maps:get(InfoHash, State#state.leecher_processes), {handshake, Handshake}),
            {noreply, State};
        _ ->
            {noreply, State}
    end;
handle_cast({reciprocal_handshake, Handshake}, State) ->
    #handshake{info_hash = InfoHash} = Handshake,
    LeecherRef = maps:get(InfoHash, State#state.leecher_processes),
    gen_server:cast(LeecherRef, {reciprocal_handshake, Handshake}),
    {noreply, State};
handle_cast({tracker_unavailable, #metainfo{announce = Tracker, info_hash = InfoHash}},
            State) ->
    logger:warning("Tracker ~s not available", Tracker),
    NewLeecherProcesses = maps:remove(InfoHash, State#state.leecher_processes),
    NewTorrents = maps:remove(InfoHash, State#state.current_torrents),
    {noreply,
     State#state{leecher_processes = NewLeecherProcesses, current_torrents = NewTorrents}};
handle_cast(_, State) ->
    {noreply, State}.

handle_info({torrent, Sender, DownloadRequest}, State) ->
    #download_request{metainfo = MetaInfo, filename = Filename} = DownloadRequest,
    case open_binary_file(Filename) of
        {ok, exists, File} ->
            case get_existent_pieces_from_file(MetaInfo, File) of
                {ok, ExistentPieces} ->
                    self() ! {tracker_request, DownloadRequest, ExistentPieces, File},
                    Sender ! file_loaded,
                    {noreply, State};
                Error ->
                    Sender ! Error,
                    {noreply, State}
            end;
        {ok, new, File} ->
            self() ! {tracker_request, DownloadRequest, sets:new(), File},
            Sender ! file_loaded,
            {noreply, State};
        {error, Reason} ->
            Sender ! {error, Reason},
            {noreply, State}
    end;
handle_info({tracker_request, DownloadRequest, ExistingPieces, File}, State) ->
    #download_request{metainfo = MetaInfo, filename = Filename} = DownloadRequest,
    #metainfo{announce = AnnounceRef, info_hash = InfoHash} = MetaInfo,
    {ok, WorkerPid} =
        ep2psharing_worker_sup:start_leecher(DownloadRequest, ExistingPieces, File),
    TorrentInfo =
        #torrent_info{announce = AnnounceRef,
                      metainfo = MetaInfo,
                      filename = Filename,
                      existent_pieces = ExistingPieces},
    NewState =
        State#state{leecher_processes =
                        maps:put(InfoHash, WorkerPid, State#state.leecher_processes),
                    current_torrents =
                        maps:put(InfoHash, TorrentInfo, State#state.current_torrents)},
    {noreply, NewState}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

open_binary_file(Filename) ->
    ExistentAtom =
        case filelib:is_regular(Filename) of
            true ->
                exists;
            false ->
                new
        end,
    case file:open(Filename, [read, write, binary]) of
        {ok, File} ->
            {ok, ExistentAtom, File};
        {error, Reason} ->
            {error, Reason}
    end.

get_existent_pieces_from_file(#metainfo{info = Info}, File) ->
    #metainfo_info_field{piece_len = PieceLen, pieces = Pieces} = Info,
    get_and_validate_pieces(lists:enumerate(Pieces), PieceLen, File, sets:new()).

get_and_validate_pieces([], _PieceLen, _File, ExistentPieces) ->
    {ok, ExistentPieces};
get_and_validate_pieces([{Index, PieceHash} | Tail], PieceLen, File, ExistentPieces) ->
    case file:pread(File, (Index - 1) * PieceLen, PieceLen) of
        {ok, Data} ->
            Digest = crypto:hash(sha, Data),
            case {check_empty_piece(Data), Digest == PieceHash} of
                {Cond1, _} when Cond1 ->
                    get_and_validate_pieces(Tail, PieceLen, File, ExistentPieces);
                {_, Cond2} when Cond2 ->
                    NewSet = sets:add_element(Index, ExistentPieces),
                    get_and_validate_pieces(Tail, PieceLen, File, NewSet);
                _ ->
                    {integrity_broken, Index}
            end;
        eof ->
            {ok, ExistentPieces};
        {error, Reason} ->
            {error, Reason}
    end.

check_empty_piece(Piece) when is_binary(Piece) ->
    lists:all(fun(X) -> X == 0 end, binary_to_list(Piece)).
