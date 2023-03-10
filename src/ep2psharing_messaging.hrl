-include("ep2psharing_metainfo.hrl").

-define(BLOCK_SIZE, 16384).
-define(MAX_SIMULTANEOUS_PIECE_REQUESTS, 5).
-define(REQUEST_TIMEOUT, 5000).
-define(POOL_OCCUPATION_TIMEOUT, 30000).

-type peer_set() :: sets:set(gen_server:server_ref()).
%%  Process on another node which associated with specific torrent
%%  Exists when peers have handshaked
-type socket() :: gen_server:server_ref() | not_handshaked.

-record(download_request, {metainfo :: #metainfo{}, filename :: file:name_all()}).
-record(announce_request,
        {info_hash :: info_hash(),
         node_id :: gen_server:server_ref(),
         event :: started | completed | stopped | empty,
         downloaded :: integer(),
         uploaded :: integer()}).
-record(announce_reply,
        {failure :: string() | none, interval :: integer(), peers :: peer_set()}).
-record(handshake,
        {info_hash :: info_hash(),
         peer_id :: gen_server:server_ref(),
         socket :: socket(),
         %%          Set of piece indices which sender has
         have :: sets:set()}).
-record(block_request,
        {%%    Zero-based piece index
         index :: integer(),
         %%    Zero-based piece offset in bytes
         offset :: integer(),
         %%    Block size in bytes
         length :: integer()}).
-record(block_reply, {index :: integer(), offset :: integer(), block :: binary()}).
-record(have_piece, {peer_id :: gen_server:server_ref(), index :: integer()}).

-type download_request() :: #download_request{}.
-type block_reply() :: #block_reply{}.
-type block_request() :: #block_request{}.
-type have_piece() :: #have_piece{}.
-type announce_request() :: #announce_request{}.
