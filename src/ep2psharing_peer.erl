%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(ep2psharing_peer).

-behaviour(gen_server).

-include("ep2psharing_messaging.hrl").

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(torrent_info,
        {announce :: gen_server:server_ref(),
         metainfo :: #metainfo{},
         filename :: file:name_all(),
         existent_pieces :: sets:set(piece_index()),
         interval :: integer()}).
-record(state, {current_torrents :: #{info_hash() => #torrent_info{}}}).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link() ->
    gen_server:start_link({local, peer}, ?MODULE, [], []).

init(_Args) ->
    {ok, #state{}}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

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
    ep2psharing_worker_sup:start_leecher(DownloadRequest, ExistingPieces, File),
    {noreply, State}.

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
    case file:open(Filename, [read, write, raw]) of
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
            DataHash = binary_to_list(Digest),
            case {check_empty_piece(Data), string:equal(PieceHash, DataHash)} of
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
