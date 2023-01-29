%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 22. янв. 2023 20:54
%%%-------------------------------------------------------------------

-include("ep2psharing_metainfo.hrl").

-type peer_set() :: [gen_server:server_ref()].

-record(download_request, {metainfo :: #metainfo{}, filename :: file:name_all()}).
-record(announce_request,
        {info_hash :: info_hash(),
         node_id :: gen_server:server_ref(),
         event :: started | completed | stopped | empty,
         downloaded :: integer(),
         uploaded :: integer()}).
-record(announce_reply,
        {failure :: string() | none, interval :: integer(), peers :: peer_set()}).
