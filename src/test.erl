-module(test).

-compile(export_all).  

set() ->
	S0 = gb_sets:new(),
	S1 =gb_sets:add_element({2, node1}, S0),
	S2 =gb_sets:add_element({2, node2}, S1),
	S3 =gb_sets:add_element({1, node14}, S2),
	S4 =gb_sets:add_element({1, node5}, S3),
	S5 =gb_sets:add_element({1, node88}, S4),
	S6 =gb_sets:add_element({4, node0}, S5),
	io:format("large=~p, small=~p~n", [gb_sets:largest(S6), gb_sets:smallest(S6)]),
	ok.

dict() ->
	D0 = dict:new(),
	D1 = dict:append(node1,1, D0),
	D2 = dict:append(node4,1, D1),
	D3 = dict:append(node6,3, D2),
	D4 = dict:append(node10,2, D3),
	D5 = dict:append(node8,1, D4),
	D6 = dict:append(node5,1, D5),
	L = dict:to_list(D6),
	io:format("L=~p~n", [L]),

	NL = for(1, length(L), fun(I) -> {Node, P} =  lists:nth(I,L), PH = lists:nth(1,P), {PH, Node} end),

	S6 = gb_sets:from_list(NL),
	io:format("gb_sets large=~p, small=~p~n", [gb_sets:largest(S6), gb_sets:smallest(S6)]),

	LL = gb_sets:to_list(S6),
	io:format("LL=~p~n", [LL]),

			ClosestId= {1,node1},
			ClosestIndex = get_index_from_list(ClosestId, 1, LL),
			%MyIndex = get_index_from_list(MyNode, 1, List),

			PrevIndex = case (ClosestIndex == 1) of
				true -> length(LL);
				false -> 
					case (ClosestIndex == 0) of
						true -> 1;	%% ClosestId is me
						false -> ClosestIndex -1
					end
			end,
			PrevClosestId = lists:nth(PrevIndex,LL),

	PrevClosestId.

get_index_from_list(Key, Index, List) ->
	case (Index > length(List)) of
		true ->
			0;	%% error
		false ->
			Key0 = lists:nth(Index,List),
			case (Key =:= Key0) of
				true -> Index;
				false -> get_index_from_list(Key, Index +1, List)
			end
	end.

run() ->
	register(shell, self()),

	receive
		{From, Msg} ->
				From ! {self(), "thanks"},
				io:format("[~p] msg:~p~n", [From, Msg])
	end.




for(Max, Max, F) -> [F(Max)];
for(I, Max, F)   -> [F(I)|for(I+1, Max, F)].