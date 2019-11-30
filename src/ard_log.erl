%%%-------------------------------------------------------------------
%%% @author  <YuQiang@YUQIANG-PC>
%%% @copyright (C) 2012, 
%%% @doc
%%% ard_log
%%% @end
%%% Created :  5 Jul 2012 by  <YuQiang@YUQIANG-PC>
%%%-------------------------------------------------------------------
-module(ard_log).
-include("ard.hrl").

-compile(export_all).  
-type logstatus() :: 'open' | 'write' | 'close' .

-record(logger, {
	status	::logstatus(),
	lines	::integer(),
	file
    }).

start(LoggerName) ->
	%put(?ARD_LOGGER, LoggerName),
	Pid = case global:whereis_name(LoggerName) of
		undefined ->
			%{ok,F} = file:open(get_atom_name(LoggerName), write),
			%LogState = #logger{status = open, lines = 0, file = F},
			Pid1 = spawn(fun() -> log_loop(LoggerName,open, 0, undefined) end),
			global:register_name(LoggerName, Pid1), 			
			Pid1;
		_Pid -> global:unregister_name(LoggerName),
				%{ok,F} = file:open(get_atom_name(LoggerName), write),
				%LogState = #logger{status = open, lines = 0, file = F},
				Pid0 = spawn(fun() -> log_loop(LoggerName,open, 0, undefined) end),
				global:register_name(LoggerName, Pid0), 
				Pid0
	end,
	Pid.


log_loop(LoggerName,Status, Lines, File0) ->
	File = case (File0 == undefined) of
		true ->
			{ok,F} = file:open(get_atom_name(LoggerName), write),
			F;
		false ->
			File0
	end,

	receive
	{state,Time, Sender, State} ->	%% record State info
		Line =Lines + 1,
		S = binary_to_term(State),
		log_msg(File, Time, Sender, S),
		%log_state_info(File, State),
		log_loop(LoggerName, write, Line, File);
	{info, Time, Sender, Msg} ->	%% write log
		Line = Lines + 1,
		M = binary_to_list(Msg),
		%{Format, Data} = Msg,
		%io:format(Format, Data),
		%io:format(File ,Format, Data), 
		log_msg(File, Time, Sender, M),

		log_loop(LoggerName, write, Line, File);
	{info, Time, Sender, Msg, State} ->	%% write log
		Line = Lines + 1,
		M = binary_to_list(Msg),
		S = binary_to_list(State),
		log_info(File,Time, Sender, M, S),
		log_loop(LoggerName, write,Line,File);
	{command,  _Me, Sender, close} -> 	%% close log file
		file:close(File),
		Me = LoggerName,	%%get(?ARD_LOGGER),
		global:send(Sender , {result, Sender, Me, {lines, Lines}}),
		log_loop(LoggerName, close, Lines, File);

	{command, Me, Sender, stop} -> %% exit
		global:unregister_name(Me),
		global:send(Sender, {result, Sender, Me, {stopped}}),
		ok
end.

log_state_info(File, State) ->
	case (File == undefined) of
	true ->
		io:format( get_state_info(State));
	false ->
		io:format("id = ~p, next = ~p, status=~p, ask=~p, sent=~p, recv=~p, round=~p ~n",
			[State#state.id,State#state.next,State#state.status,queue:len(State#state.ask), State#state.sent, State#state.recv, State#state.round]),
		io:format(File, "44 ~p id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, previous=~p, ask=~p, sent=~p, recv=~p , round=~p ~n", 
			[State#state.id,State#state.id, State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
			State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
			queue:len(State#state.previous), queue:len(State#state.ask),
			State#state.sent, State#state.recv, State#state.round])
	end.

log_msg(File, _Time, _Sender,  Msg) ->
	case (File == undefined) of
	true ->
		io:format( Msg,[]);
		%io:format( get_log_info(Msg));
	false ->
		%{Format, Data} = Msg,
		io:format(File ,Msg,[])
		%io:format(File ,Format, Data)
	end.

log_info(File, _Time, _Sender, Msg, State) ->
	case (File == undefined) of
	true ->
		io:format( Msg),
		io:format(State);

		%io:format( get_log_info(Msg)),
		%io:format( get_state_info(State));
	false ->
		io:format(File,  Msg,[]),
		io:format(File,  State,[])
		%%io:format("State=~p~n", [State]),
%		io:format(File, "33 ~p id = ~p, next = ~p, status=~p,wait = ~p,  phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, previous=~p, ask=~p, sent=~p, recv=~p, round=~p~n", 
%			[State#state.id,State#state.id,State#state.next,State#state.status,State#state.wait,State#state.phase,
%			State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
%			queue:len(State#state.previous), queue:len(State#state.ask),
%			State#state.sent, State#state.recv, State#state.round])
	end.


%	{Format, Data} = Msg,
%	io:format(Format, Data),
%%	io:format("status = ~p ~n", [State#state.status]),
%	io:format("id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p,
%	local = ~p,unaware = ~p,unexplored = ~p, done = ~p, nodes=~p, previous_size=~p, ask=~p,
%	sent=~p, recv=~p~n", 
%	[State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
%	State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
%	State#state.ids, queue:len(State#state.previous), queue:len(State#state.ask),
%	State#state.sent, State#state.recv])

%end
get_atom_name(Name) ->
	TempList1 = io_lib:format( "~p.log",[Name]),
	list_to_atom(lists:flatten(TempList1)).

get_log_info(Msg) ->
	{Format, Data} = Msg,
	TempList0 = io_lib:format(Format, Data),
	lists:flatten(TempList0 ).
	%%list_to_atom(lists:flatten(TempList0 )).


get_state_info( State)->
	TempList1 = io_lib:format( "id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, previous=~p, ask=~p, sent=~p, recv=~p, round=~p ~n", 
			[State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
			State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
			queue:len(State#state.previous), queue:len(State#state.ask),
			State#state.sent, State#state.recv, State#state.round]),
	lists:flatten(TempList1).