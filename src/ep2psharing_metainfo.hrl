%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 22. янв. 2023 20:10
%%%-------------------------------------------------------------------

-type piece_hash() :: string().
-type piece_index() :: integer().
-type info_hash() :: string().

-record(metainfo_info_field,
        {%% File's name
         name :: string(),
         %% File's piece length in bytes
         piece_len :: integer(),
         %%  Each element is the SHA1 hash of the piece at the corresponding index.
         pieces :: [piece_hash()],
         %%  File's length in bytes
         length :: integer()}).
%% Representation of metainfo (.torrent) file in Erlang record
-record(metainfo, {announce :: gen_server:server_ref(), info :: #metainfo_info_field{}}).
-record(piece_entry, {index :: integer(), hash :: piece_hash()}).
