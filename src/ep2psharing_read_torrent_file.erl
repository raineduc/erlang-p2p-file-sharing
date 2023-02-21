-module(ep2psharing_read_torrent_file).

%% API
-export([read_torrent_file/1]).
-include("ep2psharing_metainfo.hrl").

read_torrent_file(FilePath) ->
  case file:read_file(FilePath) of
    {ok, BinaryData} ->
      case bencode:decode(BinaryData) of
        {ok, DecodedData} ->
          Announce = parse_announce(maps:get(<<"announce">>, DecodedData)),
          case maps:find(<<"info">>, DecodedData) of
            {ok, InfoData} ->
              InfoField = #metainfo_info_field{
                name = binary:bin_to_list(maps:get(<<"name">>, InfoData, "")),
                piece_len = maps:get(<<"piece length">>, InfoData, 0),
                pieces = parse_pieces_data(maps:get(<<"pieces">>, InfoData, <<>>)),
                length = maps:get(<<"length">>, InfoData, 0)
              },
              InfoHash = ep2psharing_bencoding:calc_info_field_hash(InfoField),
              #metainfo{ announce = Announce, info = InfoField, info_hash = InfoHash };
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

parse_announce(BitString) ->
  Str = binary_to_list(BitString),
  [Pid, Node] = string:split(Str, ","),
  {list_to_atom(Pid), list_to_atom(Node)}.
