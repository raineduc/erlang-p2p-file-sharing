-module(ep2psharing_read_torrent_file).

%% API
-export([read_torrent_file/1, start/0]).
-include("ep2psharing_metainfo.hrl").

read_torrent_file(FilePath) ->
  case file:read_file(FilePath) of
    {ok, BinaryData} ->
      case bencode:decode(BinaryData) of
        {ok, DecodedData} ->
          case maps:find(<<"info">>, DecodedData) of
            {ok, InfoData} ->
              #metainfo_info_field{
                name = maps:get(<<"name">>, InfoData, ""),
                piece_len = maps:get(<<"piece length">>, InfoData, 0),
                pieces = parse_pieces_data(maps:get(<<"pieces">>, InfoData, <<>>)),
                length = maps:get(<<"length">>, InfoData, 0)
              };
            error ->
              io:format("Error: 'info' key not found in torrent file.~n", []),
              undefined
          end;
        error ->
          io:format("Error: failed to decode bencoded data.~n", []),
          undefined
      end;
    {error, Reason} ->
      io:format("Error: failed to read file: ~p~n", [Reason]),
      undefined
  end.

parse_pieces_data(<<>>) -> [];
parse_pieces_data(Data) ->
  <<Hash:20/binary, Rest/binary>> = Data,
  [Hash | parse_pieces_data(Rest)].

start() ->
  % read torrent file
  Metainfo = read_torrent_file("test.torrent"),
  % print info
  io:format("Torrent file info:~n", []),
  io:format("Name: ~p~n", [Metainfo#metainfo_info_field.name]),
  io:format("Piece length: ~p~n", [Metainfo#metainfo_info_field.piece_len]),
  io:format("Pieces: ~p~n", [Metainfo#metainfo_info_field.pieces]),
  io:format("Length: ~p~n", [Metainfo#metainfo_info_field.length]).