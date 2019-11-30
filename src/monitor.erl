-module(monitor).
-include("ard.hrl").

-compile(export_all).  




start(Name, Node, Aim) ->
	{_Phase0, Aimid} = Aim,
	{_Phase1, Fatherid} = Node,
	M0 = #monitor{id = Name,father = Node, fatherid = Fatherid, target = Aim, targetid = Aimid},

	M1 = mon(M0, Aim),
	%send(Fatherid , {ardmonitor, Fatherid, M1#monitor.id, {result, M1#monitor.status} }),

	loop(M1).


loop(State) ->
	Mref = State#monitor.ref,
	receive
        {'DOWN',Mref,_process, _Pid, Reason} = NodeMsg ->  %接受监控消息
		%% Caller died before sending us the go-ahead.
		%% Give up silently.
			log_info( {"~p got msg =~p.~n", [State#monitor.id, NodeMsg]}),
			send(State#monitor.fatherid, {fault, State#monitor.fatherid, State#monitor.id, {nodedown, State#monitor.target, Reason} }),
			loop(State#monitor{status = down});
		{nodedown, Node} = NodeMsg ->
			log_info( {"~p got msg =~p.~n", [State#monitor.id, NodeMsg]}),
			send(State#monitor.fatherid, {fault, State#monitor.fatherid, State#monitor.id, {nodedown, Node} }),
			loop(State#monitor{status = down});
		{monitor, _To, From,  {change, Target}} = ChangeMsg ->
			log_info( {"~p got msg =~p.~n", [State#monitor.id, ChangeMsg]}),
			{_Phase0, Targetid} = Target,
			case (State#monitor.targetid =:= Targetid) of 
				true ->
					send(From , {monitor, From, State#monitor.id, {result, Target, connected} }),
					loop(State#monitor{target = Target, targetid = Targetid, status = connected});
				false -> 
					%io:format("~p will demonitor node[~p].~n", [State#monitor.id, State#monitor.targetid]),
					log_info( {"~p will demonitor node[~p].~n", [State#monitor.id, State#monitor.targetid]}),
					if (Mref /= undefined) ->
						catch(	erlang:demonitor(Mref));
						true -> ok
					end,
					%%erlang:monitor_node(State#monitor.targetid, false),
					State1 = mon(State, Target),
					%case (State1#monitor.status =:= connected) of
					%	true ->
					%		send(From , {monitor, From, State1#monitor.id, {result, Target, State1#monitor.status} });
					%	false ->
					%		send(From, {fault, From, State#monitor.id, {nodedown, Target, nodedown} })
					%end,
					loop(State1 )
			end;
		{monitor, _To, _From,  {stop, _Target}} = StopMsg ->
			log_info( {"~p got msg =~p.~n", [State#monitor.id, StopMsg]}),
			%io:format("~p will demonitor node[~p].~n", [State#monitor.id, State#monitor.targetid]),
			log_info( {"~p will demonitor node[~p].~n", [State#monitor.id, State#monitor.targetid]}),
			catch(	erlang:demonitor(Mref)),
			
			%%erlang:monitor_node(State#monitor.targetid,false ),
			%send(From , {monitor, From,State#monitor.id, {stop, State#monitor.targetid, stopped} }),
			log_info( {"~p will exit.~n", [State#monitor.id]}),
			exit(normal);
		Other ->
			log_info( {"~p got msg =~p, do nothing.~n", [State#monitor.id, Other]}),
			loop(State )
	end.

mon(State, Aim) ->
	{_Phase, AimNode} = Aim,
	M = case erlang:whereis(AimNode) of
		undefined ->
			send(State#monitor.fatherid, {fault, State#monitor.fatherid, State#monitor.id, {nodedown, Aim, nodedown} }),
			State#monitor{ ref = undefined, target = Aim, targetid = AimNode, status = down};
		Pid ->
			%io:format("~p will monitor node[~p].~n", [State#monitor.id, AimNode]),
			log_info( {"~p go to monitor node[~p].~n", [State#monitor.id, AimNode]}),
			%%erlang:monitor_node(AimNode, true) ,
			Mref = erlang:monitor(process, Pid),
			send(State#monitor.fatherid , {monitor, State#monitor.fatherid, State#monitor.id, {result, Aim, connected} }),
			State#monitor{ ref = Mref, target = Aim, targetid = AimNode, status = connected}
	end,
	M.

send(Name, Msg) ->
	case erlang:whereis(Name) of
		undefined ->
			io:format("~p isn't exist!~n", [Name]),
			false;
		Pid -> 
			Pid ! Msg,
			true
	end.

log_info(Msg) ->
	Logger = main:ensure_logger(),
	Logger ! {info, now(), self(),  list_to_binary(get_msg_info(Msg))}.


get_msg_info(Msg) ->
	{Format, Data} = Msg,
	TempList0 = io_lib:format(Format, Data),
	lists:flatten(TempList0 ).	%%list_to_atom(