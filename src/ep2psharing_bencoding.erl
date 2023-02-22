%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. янв. 2023 23:58
%%%-------------------------------------------------------------------
-module(ep2psharing_bencoding).

-include("ep2psharing_metainfo.hrl").

%% API
-export([encode_info_field/1, calc_info_field_hash/1]).

encode_info_field(#metainfo_info_field{name = Name,
                                       piece_len = PieceLen,
                                       pieces = Pieces,
                                       length = Length}) ->
    Entries =
        [{"name", Name}, {"piecelength", PieceLen}, {"pieces", Pieces}, {"length", Length}],
    bencode:encode(
        maps:from_list(Entries)).

calc_info_field_hash(MetaInfoField) ->
    BencodedInfo = ep2psharing_bencoding:encode_info_field(MetaInfoField),
    binary_to_list(crypto:hash(sha, BencodedInfo)).
