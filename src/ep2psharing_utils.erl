-module(ep2psharing_utils).

%% API
-export([take_random_elem/1]).

take_random_elem(List) ->
    lists:nth(
        rand:uniform(length(List)), List).
