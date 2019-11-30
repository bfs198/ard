-module(main).
-include("ard.hrl").

-export([start/1]).
-export([start/2]).
-export([run/0]).
-export([ask/2]).
-export([read_config/0]).
-compile(export_all).  
-define(ARD_NODE, ard_parm).

test() ->
	ard:init_table(),
	S = read_config(),
	L = S#parm.nodes,
	io:format("nodes=~p~n", [L]),
	lists:foreach(fun(E) -> start_node(E) end, L),
	ensure_logger(),
	put(?ARD_SEND, 0),
	put(?ARD_RECEIVE, 0),
	put(?ARD_ROUND, 0),
	ok.

start(N) ->
	ard:init_table(),
	S = init(N),
	L = S#parm.nodes,
	io:format("nodes=~p~n", [L]),
	lists:foreach(fun(E) -> start_node(E) end, L),
	ensure_logger(),
	put(?ARD_SEND, 0),
	put(?ARD_RECEIVE, 0),
	put(?ARD_ROUND, 0),
%   Pid1 =spawn(fun() -> ard:start(node1,[node2]) end) ,
%   register(node1, Pid1), 
   ok.

start(N,P) ->
	ard:init_table(),
	S = init(N, P),
	L = S#parm.nodes,
	io:format("nodes=~p~n", [L]),
	lists:foreach(fun(E) -> start_node(E) end, L),
	ensure_logger(),
	put(?ARD_SEND, 0),
	put(?ARD_RECEIVE, 0),
	put(?ARD_ROUND, 0),
   ok.

start_node({I,NName,Parm} = _E) ->
	io:format("num =~p, name =~p, parms= ~p~n",[I,NName,Parm]),
	Pid1 =spawn(fun() -> ard:start(NName,Parm) end) ,
	register(NName, Pid1).

run_node({I, NName, Parm} =_E) ->
	io:format("num =~p, name =~p, parms= ~p~n",[I,NName,Parm]),
	case erlang:whereis(NName) of
		undefined ->
			io:format("~p isn't exist!~n", [NName]),
			false;
		Pid -> 
			Pid !  {init},
			true
	end.

	%NName ! {init}.

run() ->
	S = get(?ARD_NODE),
	L = S#parm.nodes,
	io:format("nodes=~p~n", [L]),
	if (is_record(S,parm)) ->			
			lists:foreach(fun(E) -> run_node(E) end, L)
	end,
%	node1 ! {init},

	ok.
ask() ->
	S = get(?ARD_NODE),
	L = S#parm.nodes,
	if (is_record(S,parm)) ->			
			lists:foreach(fun(E) -> ask(E) end, L)
	end,
	io:format("total send=~p, receive =~p, max round=~p~n",[get(?ARD_SEND), get(?ARD_RECEIVE), get(?ARD_ROUND)]),

	ok.

ask({_I, NName, _Parm} =_E) ->
	case erlang:whereis(NName) of
		undefined -> 
			io:format("~p isn't exist!~n", [NName]);
		_Pid ->
			State = ask(NName, getState),
			case (is_integer( get(?ARD_SEND) )) of
				true ->
					Send = get(?ARD_SEND) + State#state.sent,
					put(?ARD_SEND, Send),
					ok;
				false -> error
			end,
			case (is_integer( get(?ARD_RECEIVE) ))  of
				true ->
					Recv = get(?ARD_RECEIVE) + State#state.recv,
					put(?ARD_RECEIVE, Recv),
					ok;
				false -> error
			end,
			case (is_integer( get(?ARD_ROUND) )) of
				true ->
					Round0 = get(?ARD_ROUND),
					Round1=  State#state.round,
					Round = case ((State#state.id =:= State#state.next) andalso (State#state.status =:= wait)) of
						true ->
							case (Round1 > Round0) of
								true -> Round1;
								false -> Round0
							end;
						false -> Round0
					end,
					put(?ARD_ROUND, Round),
					ok;
				false -> error

			end,
			Logger = main:ensure_logger(),
			Logger ! {state, now(), self(), State}
	end.

ask(Node, Command) ->
	case erlang:whereis(Node) of
		undefined ->
			io:format("~p isn't exist!~n", [Node]),
			ard:new_state();
		Pid -> 
			Pid ! {command, Node, self(), {c,Command} },
			receive
				{result, _To, _From, Data } ->
					%io:format("got ~p 's result=  ~p", [Node, Data])
					%ard:log_state_info(Data)
					Data
			end
			
	end.

restart(Node) ->
	S = get(?ARD_NODE),
	L = S#parm.nodes,
	if (is_record(S,parm)) ->	
		{_Ok, NodeInfo} = get_info(Node, L),
		{_I, NName, _Parm} = NodeInfo,
		case erlang:whereis(NName) of
			undefined ->
				Logger = main:ensure_logger(),
				Msg= {"~p will restart.~n", [Node]},
				
				Logger ! {info, now(), self(), list_to_binary(get_msg_info(Msg))} ,
				start_node(NodeInfo),
				run_node(NodeInfo),
				true;
			Pid -> 
				io:format("~p already exist[~p]!~n", [NName, Pid]),
				false
		end
	end,
	ok.

stop() ->
	S = get(?ARD_NODE),
	L = S#parm.nodes,
	if (is_record(S,parm)) -> 
		lists:foreach(fun(E) ->
			{_I, NName, _Parm} = E,  
			ask(E),
			stop_node(NName) end, L)
	end.

stop(Min, Max) ->
	case (Max >= Min) of
		true ->
			S = get(?ARD_NODE),
			L = S#parm.nodes,
			List = get_nodes(Min, Max, L, []),
			case (length(List) >0 ) of
				true ->
					lists:foreach(fun(E) ->
						ask(E) end, List),
					lists:foreach(fun(E) ->
						{_I, NName, _Parm} = E,  
						stop_node(NName) end, List);
				false -> 
					io:format("there isn't any node from [~p] to [~p] exist!~n", [Min, Max])
			end;
		false ->
			stop(Max, Min)
	end.

get_nodes(Min, Max,From, To) ->
	case (length(From)> 0) of 
		true ->
			Node = lists:nth(1,From),
			{_I, NName, _Parm} = Node, 
			From1 = lists:delete(Node , From),
			To1 = case ((NName >= Min) andalso (NName =< Max)) of
				true ->
					lists:umerge([Node], To);
				false -> To
			end,
			get_nodes(Min, Max,From1, To1);
		false ->
			To
	end.

stop(Node) ->
	S = get(?ARD_NODE),
	L = S#parm.nodes,
	case (is_record(S,parm)) of
		true ->	
			{_Ok, NodeInfo} = get_info(Node, L),
			{_I, NName, _Parm} = NodeInfo,
			stop_node(NName)
	end,
	ok.
stop_node(NName) ->
		case erlang:whereis(NName) of
			undefined ->
				io:format("~p isn't exist!~n", [NName]),
				false;
			Pid -> 
				Pid ! {close},
				true
		end.

get_info(Name, Nodes) ->
	case (length(Nodes)>0 ) of
		true ->
			 Node = lists:nth(1,Nodes),
			 Nodes1 = lists:delete(Node, Nodes),
			 {_I, NName, _Parm} = Node,
			if (NName =:=Name ) ->
				{ok, Node};
				true ->
					get_info(Name, 	Nodes1)
			end;
		false ->
			{error,no}
		end.

close() ->
	ask() ,
	Logger = main:ensure_logger(),
	Logger ! {close}.

%	S = get(?ARD_NODE),
%	L = S#parm.nodes,
%	if (is_record(S,parm)) ->			
%			lists:foreach(fun(E) -> ask(E) end, L)
%	end,
%	unregister(?ARD_NODE),
%	unregister(?ARD_LOGGER).
read_config() ->
	{ok, Val} = file:consult("ard.ini"),
	Nodes = proplists:get_value(nodes, Val),
	NodeKeys = proplists:get_keys(Nodes),
	io:format("NodeKeys=~p~n", [NodeKeys]),
	Size = case (is_list(NodeKeys)) of
		true -> length(NodeKeys);
		false -> 0
	end,
	S = case (Size > 0) of 
		true ->
			NL = for(1, Size, fun(I) -> read_parm(I, lists:nth(I,NodeKeys), Nodes) end),
			S1 = #parm{max = Size,nodes = NL },
			S1;
		false -> S0 =#parm{max =0, nodes =[]}, S0
	end,
	put(?ARD_NODE, S),
	S.

read_parm(I,Key, Val) ->
	{I,Key,	lists:nth(1,proplists:get_all_values(Key, Val))}.

init(N) ->
	NL = for(1, N, fun(I) -> get_parm(I,N) end),

	S1 = #parm{max = N,nodes = NL },
	put(?ARD_NODE, S1),
	S1.

init(N,S) ->
	S0 = case (N > S) of
		true -> S;
		false -> N - 1
	end,
	NL = for(1, N, fun(I) -> get_parm(I,N,S0) end),

	S1 = #parm{max = N,nodes = NL },
	put(?ARD_NODE, S1),
	S1.

get_name(I) ->
	TempList = io_lib:format("node~p" , [I]),
	list_to_atom(lists:flatten(TempList)).
	%%re:replace("node{0}" , [I]).

for(Max, Max, F) -> [F(Max)];
for(I, Max, F)   -> [F(I)|for(I+1, Max, F)].

get_parm_name(Max, NN )->
	N = random:uniform(Max),
	case (N == NN) of
		true -> get_parm_name(Max, NN );
		false -> N
	end.

create_parm(Size,NN, Max, L) ->
	Name = get_name( get_parm_name(Max, NN)),

	NewL = case (not lists:member(Name,L)) of
		true -> lists:umerge([Name],L);
		false -> L
	end,
	case (length(NewL) == Size) of
		true -> NewL;
		false -> create_parm(Size, NN, Max, NewL)
	end.

get_parm(I,Max) ->
	NName = get_name(I),%5
	Num = case (Max > 10) of
		true -> random:uniform(10);%3
		false -> random:uniform(Max)
	end,
%	Num = 4,

	Parm = create_parm(Num, I, Max, []),
	{I,NName,Parm}.

get_parm(I,Max, Num) ->
	NName = get_name(I),%5
	Parm = create_parm(Num, I, Max, []),
	{I,NName,Parm}.


log_loop(File) ->
	receive
	{state,_T, _S, State} ->
		log_state_info(File, State),
		log_loop(File);
	{info, Time, Sender, Msg} ->
		log_info(File,Time, Sender, Msg),
		log_loop(File);
	{info, Time, Sender, Msg, State} ->
		log_info(File,Time, Sender, Msg,State),
		log_loop(File);
	{close} -> file:close(File)
end.

ensure_logger() ->
	case erlang:whereis(?ARD_LOGGER) of
		undefined ->			
			Pid = spawn(fun() -> 
							process_flag(trap_exit, true), 
							{ok,F} = file:open("ard.log", [write]), 
							log_loop(F) 
						end),
			register(?ARD_LOGGER, Pid), 
			Pid;
			%keep_alive(?ARD_LOGGER, log_run()),
			%erlang:whereis(?ARD_LOGGER);
		Pid -> Pid
	end.

log_run() ->
	{ok,F} = file:open("ard.log", [append]),
	log_loop(F).

keep_alive(Name, Fun) ->
    register(Name, Pid0 = spawn(Fun)),
    on_exit(Pid0, fun(_Why) -> keep_alive(Name, Fun) end).

%% on_exit(Pid, Fun) links to Pid. If Pid dies with reason Why then
%% Fun(Why) is evaluated:
on_exit(Pid, Fun) ->
    spawn(fun() -> 
		  process_flag(trap_exit, true), %% <label id="code.onexit1"/>
		  link(Pid),                     %% <label id="code.onexit2"/>
		  receive
		      {'EXIT', Pid, Why} ->      %% <label id="code.onexit3"/>
			  Fun(Why)   %% <label id="code.onexit4"/>
		  end
	  end).

get_msg_info(Msg) ->
	{Format, Data} = Msg,
	TempList0 = io_lib:format(Format, Data),
	lists:flatten(TempList0 ).	%%list_to_atom(

log_state_info(File, State) ->
	case (File == undefined) of
	true ->
		io:format( get_state_info(State));
	false ->
		io:format("id = ~p, next = ~p, status=~p, ask=~p, sent=~p, recv=~p, round =~p ~n",
			[State#state.id,State#state.next,State#state.status,queue:len(State#state.ask), State#state.sent, State#state.recv, State#state.round]),
		io:format(File, "~p id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, previous=~p, ask=~p, sent=~p, recv=~p, round=~p,closestid=~p ~n", 
			[State#state.id,State#state.id, State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
			State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
			queue:len(State#state.previous), queue:len(State#state.ask),
			State#state.sent, State#state.recv, State#state.round, State#state.closestid])
	end.

log_info(File, _Time, _Sender, M) ->
	Msg = binary_to_list(M),
	case (File == undefined) of
	true ->
		io:format( Msg, []);
		%io:format( get_log_info(Msg));
	false ->
		%{Format, Data} = Msg,
		io:format(File , Msg, [])
		%io:format(File ,Format, Data)
	end.

log_info(File, _Time, _Sender, M, S) ->
	Msg = binary_to_list(M),
	State = binary_to_list(S),
	case (File == undefined) of
	true ->
		%io:format( get_log_info(Msg)),
		%io:format( get_state_info(State));
		io:format( Msg),
		io:format(State);
	false ->
		io:format(File,  Msg,[]),
		io:format(File,  State,[])
	%	io:format(File, "~p id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, previous=~p, ask=~p, sent=~p, recv=~p,mview=~p,closestid=~p, faults=~p ~n", 
	%		[State#state.id,State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
	%		State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
	%		queue:len(State#state.previous), queue:len(State#state.ask),
	%		State#state.sent, State#state.recv, State#state.mview, State#state.closestid, length( State#state.faults)])
	end.


%	{Format, Data} = Msg,
%	io:format(Format, Data),
%%	io:format("status = ~p ~n", [State#state.status]),
%	io:format("id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p,
%	local = ~p,unaware = ~p,unexplored = ~p, done = ~p, nodes=~p, previous_size=~p, ask=~p,
%	sent=~p, recv=~p~n", 
%	[State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
%	State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
%	State#state.nodes, queue:len(State#state.previous), queue:len(State#state.ask),
%	State#state.sent, State#state.recv])

%end

get_log_info(Msg) ->
	{Format, Data} = Msg,
	TempList0 = io_lib:format(Format, Data),
	lists:flatten(TempList0 ).
	%%list_to_atom(lists:flatten(TempList0 )).


get_state_info( State)->
	TempList1 = io_lib:format( "id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, previous=~p, ask=~p, sent=~p, recv=~p ~n", 
			[State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
			State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
			queue:len(State#state.previous), queue:len(State#state.ask),
			State#state.sent, State#state.recv]),
	lists:flatten(TempList1).