%%%-------------------------------------------------------------------
%%% @author hrami
%%% @copyright (C) 2023, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. февр. 2023 23:14
%%%-------------------------------------------------------------------
-module(ep2psharing_utils).

%% API
-export([take_random_elem/1]).

take_random_elem(List) ->
    lists:nth(
        rand:uniform(length(List)), List).
