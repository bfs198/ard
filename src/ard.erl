%%%-------------------------------------------------------------------
%%% @author  <YuQiang@YUQIANG-PC>
%%% @copyright (C) 2012, 
%%% @doc
%%%
%%% @end
%%% Created :  5 Jul 2012 by  <YuQiang@YUQIANG-PC>
%%%-------------------------------------------------------------------
-module(ard).
-include("ard.hrl").


%% API
-export([start/2, start/3, run/3]).
-export([readConfig/0]).
-export([new_state/0]).
-export([log_state_info/1]).
-export([get_state_info/1]).

%% gen_fsm callbacks
-export([init/2, terminate/3]).

-define(SERVER, ?MODULE).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start(Localnode, Nodes) ->
 io:format("~p Resource Discovery starting~n", [Localnode]),
   {_Ok, _Status, State} = init(Localnode, Nodes),
 %%   {next_state, _NextStateName, NextState} = loop_state([],Status, State),
   loop(State).

start(Localnode, Nodes, Logger) ->
 Pid = case global:whereis_name(Localnode) of
		undefined ->
			Pid0 = run(Localnode, Nodes, Logger) ,
			Pid0;
		_Pid -> 
			global:unregister_name(Localnode),
			Pid1 = run(Localnode, Nodes, Logger),
			Pid1
	end,
	global:register_name(Localnode, Pid),
	global:sync(),
	%io:format("~p pid=~p, registered_names=~p~n", [Localnode, Pid, global:registered_names()]),
	Pid.

run(Localnode, Nodes, Logger) ->
	io:format("~p Resource Discovery starting, nodes=~p, logger=~p~n", [Localnode,Nodes, Logger]),
	%register_logger(Logger),
   {_Ok, _Status, State} = init(Localnode, Nodes),
%global:register_name(Localnode, self()),
	Pid1 = spawn(fun() -> loop(State#state{logger = Logger}) end),
	Pid1.

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @spec init(Args) -> {ok, StateName, State} |
%%                     {ok, StateName, State, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @end
%%--------------------------------------------------------------------
init(Localnode, Nodes) ->
   % io:format("Resource Discovery starting~n"),
	S1 = #state{status= explore,name = Localnode, id=Localnode ,next = Localnode, phase =1, round =1,
		more =[Localnode] ,local = Nodes, unaware = [],unexplored =[],done = [],
		previous = queue:new(), ask = queue:new(), answer = queue:new(), 
		wait = undefined , waiting =false },
	%init_table(S#state.name),
	%log_info({"Initialize State = ~p ~n", [S1#state.status] },S1),

	%record_state(S1),
    {ok, explore, S1}.

new_state() ->
	S1 = #state{ phase =0, round =0,
		more =[] ,local = [], unaware = [],unexplored =[],done = [],
		previous = queue:new(), ask = queue:new(), answer = queue:new(), 
		wait = undefined , waiting =false },
		S1.

loop(State) ->
	case (get(?LOCAL_NODE) == undefined ) of
		true ->
			register_logger(State#state.logger),
			put(?ARD_LOGGER, State#state.logger),
			put(?LOCAL_NODE, State#state.id);
		false -> ok
	end,

	NextState =
		receive

		{init} ->
			register_logger(State#state.logger),
			put(?ARD_LOGGER, State#state.logger),
			put(?LOCAL_NODE, State#state.id),
			{_Next_state, _NextStateName, NState} = loop_state([], explore , State),
			NState;
		{command, _To, From, _Command} ->
			%log_info({"~n command is ~p~n", [Command]}),
			From ! {result,From, self(),  State},	%%get_state_info( State)
			State;
		{terminate, _To, From, _Command} ->
			From ! {result,From, self(), {ok}},
			State ;
		{Action, To, From , Event }  ->
			{_next_state, _NextStatus, NState} = loop_state({Action, To, From , Event } , State#state.status, State),
			NState

	after infinity ->
		true
	end,
	log_info({"~p 's State is ~p~n", [NextState#state.id, NextState#state.status]}),
	Recv = NextState#state.recv + 1,
	loop(NextState#state{recv = Recv}).

loop_state( Msg, _Status, State) ->
	  {_Next_state, _NextStateName0, NextState0} = case State#state.status of 
		explore ->
			explore( Msg, State);
		wait ->
			wait( Msg, State);
		passive ->
			passive( Msg, State);
		inactive ->
			inactive( Msg, State);
		conquered ->
			conquered( Msg, State);
		conqueror ->
			conqueror( Msg, State)
	end,

	NextState1 = case ( (queue:len(NextState0#state.ask) > 0)  
		and ((NextState0#state.status =:= wait) or (NextState0#state.status =:= passive))
		and (NextState0#state.status  /=  State#state.status) %% status has changed.
		) of 
			true -> 
				{M1, Sender} = queue:head(NextState0#state.ask),
				case (wait_prepare_search(Sender, M1, NextState0) ) of
					true -> wait_search_queue(NextState0);
					false -> NextState0
				end;
			false -> NextState0
	end,
	NextState2 = case ( (queue:len(NextState1#state.ask) > 0)  
		and ((NextState1#state.status =:= passive))
		and (NextState1#state.status  /=  State#state.status) %% status has changed.
		) of 
			true -> wait_search_queue(NextState1);
			false -> NextState1
	end,

	NextState = case ( (queue:len(NextState2#state.ask) > 0)  
		and (NextState2#state.status =:= inactive) 		
		and (NextState2#state.status  /=  State#state.status)%% status has changed.
		) of 
		true -> %%inactive can not change again, so perform search msg right now.
			NextState3 = inactive_search_queue(NextState2),
			NextState3;
		false -> NextState2
	end,


	{next_state, NextState#state.status, NextState} 
.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec explore(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
explore(Event, State) ->
	log_info({"~p[~p] got msg = ~p ~n", [State#state.id, State#state.status ,Event]}),

	NextState = explore_state(Event, State),	
	log_info({"~p explore Next State = ~p, wait for ~p ~n", 
		[NextState#state.id ,NextState#state.status, NextState#state.wait] },NextState),
	record_state(NextState),
    {next_state, NextState#state.status, NextState}.

explore_state(Event,State) ->

			case Event of
				{queryy, To, From, {Size}} ->
					inactive_query(From, To, Size, State);
			 	{query_reply, _To, From, X }  ->	
					log_info({"~p[~p] got query_reply ~p from ~p~n",[State#state.id,State#state.status, Event, From]}),
			 		%Reply = {query_reply, To, From,X },
					%Recv = State#state.recv + 1,
					{Result,NewState} = read_query_reply(From, X, State),
					case (Result == true) of 
						true ->%% go explore
							explore_state(nothing, NewState);%%goto explore again to read unexplored.
						false ->%% continue reading from More
							explore_more(NewState)
					end;
			 		%{Reply, State#state{recv = Recv}}	;
				{search, _To, From, M} -> 
					case (wait_prepare_search(From, M, State)) of
						true -> wait_search(From, M, State);	%% status not changed
						false ->
							log_info({"~p[explore] got a search msg=~p from ~p, enqueue it. ~n", [State#state.id, M ,From]}),
							State0 = record_search_state(M, State),
							Q = queue:in({M, From}, State0#state.ask),
							explore_state(nothing, State0#state{ask = Q})
					end;
				{release, _To, _From, {Vid, merge, _Uid}} ->
					send(Vid,{merge_accept,Vid, State#state.id, {State#state.id } }),
					Sent = State#state.sent + 1,
					State#state{status = conqueror, wait = Vid, sent = Sent};
				{info, _To, _Form, _M} ->
					{_N, _S, NState} = conqueror( Event, State#state{status = conqueror}),
					NState;
				Other ->
					log_info({"~p[explore] got a msg=~p, State.unexplored=~p ~n", [State#state.id, Other, State#state.unexplored]}),
					case (length(State#state.unexplored) >0) of
						true ->
							Uid = lists:nth(1,State#state.unexplored),
							log_info({"~p got ~p from unexplored, more =~p, done =~p.~n",[State#state.id, Uid, State#state.more, State#state.done]}),
							case ((Uid  /=  State#state.id) andalso
								(not lists:member(Uid, State#state.more)) andalso (not lists:member(Uid, State#state.done))
								) of
								true ->
									Uids = lists:delete(Uid,State#state.unexplored),
									%% send a search message <id,phase,uid, false>
									log_info({"~p send search msg to ~p~n",[State#state.id, Uid]}),
									send(Uid,{search, Uid, State#state.id, {State#state.id, State#state.phase, Uid, false}}),
									Sent = State#state.sent + 1,
									NewState = State#state{status= wait, unexplored = Uids, wait = Uid, sent = Sent},
									%%io:format("explore NewState = ~p ~n", [NewState]),
		 							NewState;
								false ->	%% send query msg to it
									Unexplored =lists:delete(Uid, State#state.unexplored),
									More =lists:umerge([Uid], State#state.more),
									explore_state(ok, State#state{more = More, unexplored = Unexplored})
							end;
						false ->
							NewState= explore_more(State#state{wait = undefined}),
							%%io:format("explore NewState = ~p ~n", [NewState]),
    						NewState
					end
	
    end.
	
explore_more(State) ->
	case (length(State#state.more) >0) of
		true ->
			Uid = lists:nth(1,State#state.more),
			Size = length(State#state.more) + length(State#state.done) +1,
			case (Uid =:= State#state.id) of %% send to itself
				true ->
					{Reply, NewState0} = get_query_reply_myself(Uid, Size, State) ,

					 log_info({"~p[~p] get_query_reply= ~p ~n", [State#state.id, State#state.status, Reply]}),
					{query_reply,_To, _From, X } = Reply,
					{Result,NewState} = read_query_reply(Uid, X, NewState0),
					case (Result =:= true) of
						true ->%% go explore
							explore_state(ok, NewState);%%goto explore again to read unexplored.
						false ->
							explore_more(NewState)
					end;			
				false ->
					log_info({"~p send query[~p] to ~p~n",[State#state.id,Size, Uid]}),
					Sent = State#state.sent + 1,
					send(Uid,{queryy, Uid, State#state.id,  {Size} }),
					State#state{sent = Sent}
				end;
		false ->
			NewState1 = State#state{status=wait }, NewState1
	end.

get_query_reply_myself(Uid, Size, State) -> %% send to itself

	log_info({"~p send query to itself ~p~n",[State#state.id, Uid]}),
	{Reply, NewState0} = query_create_reply({queryy, Uid, State#state.id,  {Size} }, State),
	{Reply, NewState0}.
	
query_create_reply({queryy,_To, _From, {Size} }, State) ->
	case (Size > length(State#state.local) ) of
		true ->
			Uids = State#state.local,
			{ {query_reply,_To, _From,{Uids, true} } , State#state{ local =[]} };
		false ->
			{Uids, Local} = lists:split(Size, State#state.local),
			{ {query_reply,_To, _From,{Uids, false} } , State#state{ local = Local} }
	end.

read_query_reply(Uid,{Uids, Flag}, State) ->
	NewState0 = case  (Flag == true) of
		true ->
			More =lists:delete(Uid, State#state.more),
			Done =lists:umerge([Uid], State#state.done),
			%conquer_notify_node(State#state{more = More,done = Done }),%% notify all for node info
			State#state{more = More,done = Done, ids= Done }	;
		false ->
			State
		end,
		
	MoreDone = lists:umerge(NewState0#state.more, NewState0#state.done),
	%log_info({"~p 's MoreDone= ~p~n",[NewState0#state.id, MoreDone]}),
	Less = lists:dropwhile(fun(E) -> lists:member(E, MoreDone) end, Uids),
	%Unexplored0 = lists:umerge(NewState0#state.unexplored, Less ),
	%log_info({"~p 's Less= ~p~n",[NewState0#state.id, Less]}),
	{Result, NewState} = case (length(Less) > 0) of
		true ->
			{true, NewState0#state{unexplored = lists:umerge(NewState0#state.unexplored,Less )}};
		false ->
			{false,NewState0}
		end,
	%log_info({"~p 's unexplored= ~p~n",[NewState0#state.id, NewState#state.unexplored]}),
	{Result,NewState}.
	


%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec wait(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
wait(Event, State) ->
	log_info({"~p[~p] got msg = ~p ~n", [State#state.id, State#state.status ,Event]}),
	NewState =
	 case Event of
		{queryy, To, From, {Size}} ->
			inactive_query(From, To, Size, State);
		{query_reply, _To, From, X }  ->	
			log_info({"~p[~p] got query_reply ~p from ~p~n",[State#state.id,State#state.status, Event, From]}),
			{_Result,NewState0} = read_query_reply(From, X, State),
			NewState0;
		{search, _To, From, M} -> %{Vid, Vphase, Uid, New}
			case (wait_prepare_search(From, M, State)) of
				true -> wait_search(From, M, State);	%% status not changed
				false ->
					log_info({"~p got search msg ~p,from ~p, enqueue it. ~n", [State#state.id, Event, From]}),
					State0 = record_search_state(M, State),
					Q0 = queue:in({M, From}, State0#state.ask),%
					{M1, Yid} = queue:head(Q0),
					log_info({"~p[wait] got msg = ~p from queue by ~p, wait for ~p ~n", [State#state.id , M,Yid,State#state.wait]}),
					Q = queue:tail(Q0),
					wait_search(Yid, M1, State0#state{ask = Q})
			end;
		{release, _To , _From, {Vid, abort, _Uid}} ->
			%%N = search_release_commit_state( {Vid, abort, Uid}, State),
			case (Vid  /=  State#state.id) of
				true ->
					State#state{status = passive, wait = undefined};%%, unexplored = N#state.unexplored};
				false ->
					State
			end;
		{release, _To, _From, {Vid, merge, _Uid}} ->
			%%N = search_release_commit_state( {Vid, merge, Uid}, State),
			send(Vid,{merge_accept,Vid, State#state.id, {State#state.id } }),
			log_info({"~p[~p] send merge_accept msg to  ~p ~n",[State#state.id,State#state.status, Vid]}),
			Sent = State#state.sent + 1,
			State#state{status = conqueror, wait = Vid, sent = Sent};	%%, unexplored = N#state.unexplored};
		_M ->
			log_info({"~p[~p] do nothing at msg= ~p ~n",[State#state.id,State#state.status, Event]}),
			State
	end,

	NextState = case ( (NewState#state.wait =:= undefined) 
		andalso (NewState#state.status =:= wait)  andalso (State#state.status =:= wait) %% status not changed
		andalso( (length(NewState#state.unexplored) > 0) orelse (length(NewState#state.more) > 0) )
		) of
		true ->  %% status is dead for wait
			%%will goto explore
			explore_myself(NewState), 
			log_info({"~p[~p] send explore msg to itself.~n", [NewState#state.id, NewState#state.status ] }),
			Sent1 = NewState#state.sent + 1,
			NewState#state{status = explore, sent = Sent1};
		false -> NewState
	end,
	log_info({"~p wait Next State = ~p , wait =~p~n", [State#state.id ,NextState#state.status, State#state.wait] },NextState),
	record_state(NextState),
	{next_state, NextState#state.status, NextState}.


wait_search_queue(State) ->

	case ((queue:len(State#state.ask) > 0) and ((State#state.status =:= wait) 
		or (State#state.status =:= inactive) or (State#state.status =:= passive)))of
		true ->
			{M, Yid} = queue:head(State#state.ask),
			log_info({"~p[~p] got msg = ~p from queue by ~p, wait for ~p ~n", [State#state.id ,State#state.status, M,Yid,State#state.wait]}),
			Q = queue:tail(State#state.ask),

			wait_search(Yid, M, State#state{ask = Q});
		false ->  State
	end.

record_search_sender({Vid, _Vphase, _Uid, _New}, State) ->
	%% some send to search me, but i do not know sender
	State0 = case ( (State#state.wait  /=  Vid) and 
		(not lists:member(Vid, State#state.local)) and 
		%%(not lists:member(Vid, State#state.unaware)) and
		(not lists:member(Vid, State#state.more)) and
		(not lists:member(Vid, State#state.unexplored)) and
		(not lists:member(Vid, State#state.done))  
		) of
		true ->
			log_info({"~p donot know search msg's sender[~p], [unexplored] add it.~n", [State#state.id, Vid ]}),
			More0 = lists:umerge([Vid], State#state.unexplored),
			%% send a search message <id,phase,uid, false>
			%send(Vid,{search, Vid, State#state.id, {State#state.id, State#state.phase, Vid, false}}),
			State#state{unexplored = More0 };	
		false -> State
		end,
		State0.

wait_search_sender({Vid, _Vphase, _Uid, _New}, State) ->
%%log_info({"~p State.unexplored=~p~n", [State#state.id, State#state.unexplored]}),

	case ((State#state.wait  /=  Vid) and 
		(not lists:member(Vid, State#state.local)) and 
		%%(not lists:member(Vid, State#state.unaware)) and
		(not lists:member(Vid, State#state.more)) and
		(not lists:member(Vid, State#state.unexplored)) and
		(not lists:member(Vid, State#state.done))  and
		(State#state.status  /=  passive)  %% passive can not send search msg again.
		) of
		true ->
			log_info({"~p donot know search msg's sender[~p], send search msg to it.~n", [State#state.id, Vid ]}),
			%% send a search message <id,phase,uid, false>
			send(Vid,{search, Vid, State#state.id, {State#state.id, State#state.phase, Vid, false}}),
			Sent = State#state.sent + 1,
			State#state{sent = Sent};	
		false -> State
		end.

record_search_state( {_Vid, _Vphase, Uid, New} = _M, State) ->
	case ((New == true) andalso (lists:member(Uid, State#state.done))) of
		true ->
			Done =lists:delete(Uid, State#state.done),
			More =lists:umerge([Uid], State#state.more),
			State#state{more = More,done = Done };	
		false -> State
	end.

wait_prepare_search(_Sender, {Vid, Vphase, _Uid, _New} = _M, State) ->
	%log_info({"~p[~p] got msg = ~p, wait for ~p ~n", [State#state.id,State#state.status ,{Vid, Vphase, Uid, New},State#state.wait]}),
	NewState0 = State,
	Vname = Vid,
	Name = State#state.id,
	Result = case ((Vphase > NewState0#state.phase) orelse ((Vphase == NewState0#state.phase) andalso (Vname > Name)) )	of
		true ->
			false;%%State#state{status = conquered, wait = Vid};
		false ->
			true	%%State	%%State's status not changed
		end,
	Result.

wait_search(Sender, {Vid, Vphase, Uid, New}, State) ->


	log_info({"~p[~p] got msg = ~p, wait for ~p ~n", [State#state.id,State#state.status ,{Vid, Vphase, Uid, New},State#state.wait]}),
	NewState0 = State,
%	NewState0 = case ((New =:= true) and (lists:member(Uid, State0#state.done))) of
%		true ->
%			Done =lists:delete(Uid, State0#state.done),
%			More =lists:umerge([Uid], State0#state.more),
%			State0#state{more = More,done = Done };	
%		false -> State0
%	end,
	Vname = Vid,
	Name = State#state.id,
	NextState = case ((Vphase > NewState0#state.phase) orelse ((Vphase == NewState0#state.phase) andalso (Vname > Name)) )	of
		true ->
			State0 = case (Vid  /=  State#state.wait ) of
				true ->
					record_search_sender({Vid, Vphase, Uid, New}, State);	
				false -> State
			end,

			log_info({"~p[~p] send (release{~p, merge, ~p}) msg to ~p ~n", [State#state.id,State#state.status,State#state.id, Vid,Sender]}),
			send(Sender, {release,Sender, NewState0#state.id, {NewState0#state.id, merge, Vid} }),	
			Sent = NewState0#state.sent + 1,
			%Unexplored = case ((NewState0#state.wait  /=  undefined) andalso (NewState0#state.wait  /=  Sender)) of
			%	true -> lists:umerge([NewState0#state.wait], NewState0#state.unexplored);
			%	false -> NewState0#state.unexplored
			%end,
			State0#state{status = conquered, wait = Vid, sent = Sent};
		false ->
			%% State00 = wait_search_sender({Vid, Vphase, Uid, New}, State),
			%% some send to search me, but i do not know sender
			State0 = case (Vid  /=  State#state.wait ) of
				true ->
					record_search_sender({Vid, Vphase, Uid, New}, State);	
				false -> State
			end,

			log_info({"~p[~p] send (release{~p, abort, ~p}) msg to ~p ~n", [State#state.id,State#state.status,State#state.id, Vid,Sender]}),
			send(Sender, {release,Sender, NewState0#state.id, {NewState0#state.id, abort, Vid} }),
			Sent = NewState0#state.sent + 1,
			NewState01 = wait_search_sender({Vid, Vphase, Uid, New}, State0#state{sent = Sent}),
			NewState01 %%#state{ wait = undefined}
		end,	


%	{_S,NextState} = case  (NewState1#state.status =:= State#state.status) of	%%status not changed
%		true -> %% can do next search msg.
%			{Status, NextState2} = wait_search_queue(NewState1),
%			{Status, NextState2} ;
%		false -> {NewState1#state.status, NewState1}
%	end,
	NextState.
	
%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec passive(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
passive(Event, State) ->
	log_info({"~p[~p] got msg = ~p ~n", [State#state.id, State#state.status ,Event]}),
	 NextState = case Event of
		{queryy, To, From, {Size}} ->
			 inactive_query(From, To, Size, State);
		{query_reply, _To, From, X }  ->	
			log_info({"~p[~p] got query_reply ~p from ~p~n",[State#state.id,State#state.status, X, From]}),
			{_Result,NewState} = read_query_reply(From, X, State),
			NewState;
		{search, _To, From, M} ->% {Vid, Vphase, Uid, New}
			case (wait_prepare_search(From, M, State)) of
				true -> wait_search(From, M, State);	%% status not changed
				false ->
					log_info({"~p got search msg ~p,from ~p, enqueue it. ~n", [State#state.id, Event, From]}),
					State0 =record_search_state(M, State),
					Q0 = queue:in({M, From}, State0#state.ask),%
					{M1, Yid} = queue:head(Q0),
					log_info({"~p[~p] got msg = ~p from queue by ~p, wait for ~p ~n", [State#state.id, State#state.status, M,Yid,State#state.wait]}),
					Q = queue:tail(Q0),
					wait_search(Yid, M1, State0#state{ask = Q,  wait = Yid})
			end;
		{release, _To, _From, {Vid, merge, _Uid}} ->
			log_info({"~p[~p] got release merge msg ~p, send merge_fail to ~p. ~n", [State#state.id,State#state.status , Event, Vid]}),
			%%NewState = search_release_commit_state( {Vid, merge, Uid}, State),
			send(Vid ,{merge_fail, Vid, State#state.id, {State#state.id } }),
			Sent = State#state.sent + 1,
			State#state{sent = Sent};	%%, unexplored = NewState#state.unexplored};
		{merge_accept, _To, _From, {Vid}} ->	%% act as conquerd and then go inactive
			conquered_accept(Vid, State);
		_Other ->
			log_info({"~p do nothing at msg= ~p ~n",[State#state.id, Event]}),
			State
		end,	
		log_info({"~p passive Next State = ~p ~n", [State#state.id ,NextState#state.status] },NextState),
		record_state(NextState),
		{next_state, NextState#state.status, NextState}.

	
%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec inactive(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
inactive(Event, State) ->
	log_info({"~p[~p] got msg = ~p ~n", [State#state.id, State#state.status ,Event]}),
	 NextState = case Event of
		{queryy, To, From, {Size}} ->
			inactive_query(From, To, Size, State);
		{search, _To, From, Msg} ->
			log_info({"~p[~p] got search msg,enqueue = ~p ~n", [State#state.id, State#state.status,Msg]}),
			%%State0 =record_search_state(Msg, State),
			Q = queue:in({Msg, From}, State#state.ask),
			inactive_search_queue(State#state{ask = Q});
			%inactive_search(To, From, Msg, State);
		{release, To, From, {Vid, Answer, Uid}} ->
			inactive_release(To, From, {Vid, Answer, Uid}, State);
		{conquer, _To, _Form , {Vid}} ->
			inactive_conquer(Vid, State);
		{notify, _To, _Form , {Nodes}} ->	%% nodes info
			inactive_notify(Nodes, State);
		_Other ->
			log_info({"~p do nothing at msg= ~p ~n",[State#state.id, Event]}),
			State
		end,	
		log_info({"~p[~p] Next State = ~p ~n", [State#state.id, State#state.status ,NextState#state.status] },NextState),
		record_state(NextState),
		{next_state, NextState#state.status, NextState}.

%% node record all nodes info.
inactive_notify(Nodes, State) ->
	State#state{ids= Nodes, wait = undefined}.

inactive_query(Sender, _Receiver, Size, State) ->
	log_info({"~p[~p] got query from ~p ~n", [State#state.id,State#state.status ,Sender]}),

	NextState =	case (Size >= length(State#state.local) ) of
		true ->
			Uids = State#state.local,
			send(Sender, {query_reply, Sender, State#state.id, {Uids, true}}),
			Sent = State#state.sent + 1,
			log_info({"~p[~p] send query_reply{~p, true} to ~p ~n", [State#state.id,State#state.status,Uids ,Sender]}),
			State#state{ local =[], sent =Sent };
		false ->
			{Uids, Local} = lists:split(Size, State#state.local),
			send(Sender , {query_reply, Sender, State#state.id, {Uids, false}}),
			Sent = State#state.sent + 1,
			log_info({"~p[~p] send query_reply{~p, false} to ~p ~n", [State#state.id,State#state.status,Uids ,Sender]}),
			State#state{ local = Local, sent = Sent }
	end,
	NextState.

inactive_search_queue(State) ->
	case ((queue:len(State#state.ask) > 0) and (State#state.status =:= inactive) )of
		true ->
			{M, Yid} = queue:head(State#state.ask),
			log_info({"~p[~p] dequeue search msg = ~p from ~p~n", [State#state.id,State#state.status, M, Yid]}),
			{_Vid, _Vphase, Uid, _New}= M,
			Q = queue:tail(State#state.ask),
			NewState = inactive_search_message(Uid, Yid, M, State#state{ask = Q}),
			inactive_search_queue(NewState);
			%NewState;
		false ->  State
	end.

inactive_search_message(To, Sender,{Vid, Vphase, Uid, _New}= Msg, State) ->
	{M, NewState0} = case ( (State#state.id =:= Uid) and (not lists:member(Vid, State#state.local)) ) of
		true ->
			Local = lists:umerge([Vid], State#state.local),
			{{search, To, Sender,{Vid, Vphase, Uid, true}}, State#state{local = Local}};
		false -> 
			{{search, To, Sender,Msg}, State}
	end,
	%Q = NewState0#state.previous,

	{search, _, _,{_, _, _, New1}} = M,
	case ((Vid =:= NewState0#state.next) and (Uid =:= NewState0#state.id)) of 
	true ->
		log_info({"~p[~p] got search msg from leader ~p, ignore it.~n", [State#state.id,State#state.status, NewState0#state.next ]}),
		NewState0;%% leader send search msg to me, ignore it.
	false ->	%% other node send search msg to me, do it.
		Q = queue:in({M, Sender},NewState0#state.previous),
		Sent = case (queue:len(Q) == 1) of 
			true ->
				{search, To, _From,{Vid, Vphase, Uid, New1}} = M,
				send(NewState0#state.next, {search, NewState0#state.next, NewState0#state.id,{Vid, Vphase, Uid, New1}}),
				log_info({"~p[~p] forward search msg ~p to leader ~p~n", [State#state.id,State#state.status,{Vid, Vphase, Uid, New1}, NewState0#state.next ]}),

				NewState0#state.sent + 1;
			false -> NewState0#state.sent
		end,
		NewState0#state{previous = Q, sent = Sent}
	end.


inactive_release(_To, _From, {Vid, Answer, Uid}, State) ->
	case ( State#state.id =:= Uid) of
		true ->%% end receiver is me
			%%N = search_release_commit_state( {Vid, Answer, Uid}, State),
			case (Answer =:= merge) of
				true ->
					log_info({"~p[~p] got release merge msg, send merge_fail to ~p~n", [State#state.id,State#state.status,Vid ]}),
					send(Vid,{merge_fail,Vid, State#state.id, {State#state.id } }),
					Sent = State#state.sent + 1,
					Local = lists:umerge([Vid], State#state.local),
					State#state{sent = Sent, local = Local};	%%, unexplored = N#state.unexplored};
				false -> 
					log_info({"~p[~p] got release abort msg from ~p, do nothing.~n", [State#state.id,State#state.status,Vid ]}),
					State	%%#state{ unexplored = N#state.unexplored}	%% ignore the abort msg
			end;
		false -> %% release msg for last forword msg
			%{_Key,{_M,Yid},Tree} = gb_trees:take_smallest(State#state.previous),
			{_M,Yid} = queue:head(State#state.previous),
			Q = queue:tail(State#state.previous),
			Next = Vid,
			send(Yid, {release, Yid, State#state.id, {Vid, Answer, Uid}}),%% forward release msg
			Sent0 = State#state.sent + 1,
			log_info({"~p[~p] forward release msg to ~p~n", [State#state.id,State#state.status,Yid ]}),

			case (queue:len(Q) > 0) of 
				true ->
					%{_Key1,{M1,_Yid1}} = gb_trees:smallest(Tree),
					{M1,_Yid1} = queue:head(Q),
					{search, _To1, _From1, Msg} = M1,
					send(Next, {search, Next, State#state.id, Msg  }),
					log_info({"~p[~p] forward search msg ~p to leader ~p~n", [State#state.id,State#state.status,M1, Next]}),
					State#state{next = Next, previous = Q, sent = (Sent0 + 1)};
				false -> 
					inactive_search_queue(State#state{next = Next, previous = Q, sent = Sent0})
			end
			
	end.

inactive_conquer(Vid, State) ->
	Next = Vid,
	case (length(State#state.local) ==0 ) of
		true ->
			log_info({"~p[~p] send done msg to ~p~n", [State#state.id,State#state.status,Vid ]}),
			send(Vid,{done, Vid,  State#state.id,{ State#state.id}});
		false ->	
			log_info({"~p[~p] send more msg to ~p~n", [State#state.id,State#state.status,Vid ]}),
			send(Vid,{more, Vid,  State#state.id,{ State#state.id}})
	end,

	Sent = State#state.sent + 1,
	State#state{next = Next, sent = Sent, wait = undefined}.	

	
%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec conquered(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
conquered(Event, State) ->
	log_info({"~p[~p] got msg = ~p ~n", [State#state.id, State#state.status ,Event]}),
	NextState = case Event of
		{queryy, To, From, {Size}} ->
			inactive_query(From, To, Size, State);
		{query_reply, _To, From, X }  ->	
			log_info({"~p[~p] got query_reply ~p from ~p~n",[State#state.id,State#state.status, X, From]}),
			{_Result,NewState} = read_query_reply(From, X, State),
			NewState;
		{release, _To, _From, {Vid, Answer, Uid}} ->
			conquered_release(Vid, Answer, Uid, State);
		{merge_fail, _To, From, {_Vid}} ->
			log_info({"~p[~p] got merge_fail ~p from ~p, go explore again!~n",[State#state.id,State#state.status, Event, From]}),
			%%will goto explore
			explore_myself(State), 
			log_info({"~p[~p] send explore msg to itself.~n", [State#state.id, State#state.status ] }),
			Unexplored = case (State#state.wait  /=  undefined) of
				true -> lists:umerge([State#state.wait], State#state.unexplored);
				false -> State#state.unexplored
			end,
			Sent = State#state.sent + 1,
			State#state{status = explore, sent = Sent, unexplored = Unexplored};	
			%%State#state{status = passive};	
		{merge_accept, _To, _From, {Vid}} ->
			conquered_accept(Vid, State);
		{search, To, From, Msg} -> % previous.enqueue()
			conquered_search(To, From, Msg, State);
		_Other ->
			log_info({"~p do nothing at msg= ~p ~n",[State#state.id, Event]}),
			State
		end,
	log_info({"~p conquered Next State = ~p, wait =~p ~n", [State#state.id ,NextState#state.status,NextState#state.wait ] },NextState),
	record_state(NextState),
	{next_state, NextState#state.status, NextState}.


conquered_release(Vid, Answer, Uid, State) ->
	%%N = search_release_commit_state( {Vid, Answer, Uid}, State),
	case (Answer =:= merge) of
		true ->
			log_info({"~p[~p] got release msg from ~p~n", [State#state.id, State#state.status, Vid ]}),
			Unexplored = case (Uid =:= State#state.id) of
				true ->%% record sender into [unexplored]
					  lists:umerge([Vid], State#state.unexplored);
				false -> State#state.unexplored
			end,
			send(Vid,{merge_fail, Vid,  State#state.id,{ State#state.id}}),
			log_info({"~p[~p] send merge_fail msg to ~p~n", [State#state.id, State#state.status, Vid ]}),
			Sent = State#state.sent + 1,
			State#state{status = conquered, sent = Sent, unexplored = Unexplored};		
		false -> 
			log_info({"~p[~p] got release abort from ~p, do nothing.~n", [State#state.id, State#state.status, Vid ]}),
			State %% #state{unexplored = N#state.unexplored}
	end.

conquered_accept(Vid, State) ->
	send(Vid, {info, Vid, State#state.id,{State#state.phase, State#state.more, 
		State#state.done, State#state.unaware,State#state.unexplored }}),
	log_info({"~p[~p] send info ~p msg to  ~p ~n", [State#state.id,State#state.status, {State#state.phase, State#state.more, 
		State#state.done, State#state.unaware,State#state.unexplored }, Vid]}),
	Sent = State#state.sent + 1,
	State#state{next = Vid, status = inactive, wait = Vid, sent = Sent}.

conquered_search(_To, Sender, Msg, State) ->
	log_info({"~p[~p] conquered got search msg,enqueue = ~p ~n", [State#state.id, State#state.status, Msg]}),
	%Tree = gb_trees:insert({1,now()},{Msg, Sender}, State#state.previous),
	%%State0 = record_search_state(Msg, State),
	Q = queue:in({Msg, Sender}, State#state.ask),
	State#state{ask = Q}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec conqueror(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
conqueror(Event, State) ->
	log_info({"~p[~p] got msg = ~p ~n", [State#state.id, State#state.status ,Event]}),

	{GoFlag, NextState0 } = case Event of
		{queryy, To, From, {Size}} ->
			{false, inactive_query(From, To, Size, State)};
		{query_reply, _To, From, X }  ->	
			log_info({"~p[~p] got query_reply ~p from ~p~n",[State#state.id,State#state.status, X, From]}),
			{_Result,NewState} = read_query_reply(From, X, State),
			{false, NewState};
		{conquer,_To,_From,{Vid}} ->
			{false, inactive_conquer(Vid, State)};
		{search, _To, From ,M} ->
			case (wait_prepare_search(From, M, State)) of
				true -> {false, wait_search(From, M, State)};	%% status not changed
				false ->
					log_info({"~p[~p] enqueue search msg in ask queue. ~n", [State#state.id,State#state.status]}),
					State0 = record_search_state(M, State),
					Q = queue:in({M, From},State0#state.ask),
					{false, State0#state{ask = Q}}
			end;
		{release, _To, _From, _M} ->
			{false, conqueror_release(Event, State)};
		{info, _To, _From, {Lphase, Lmore, Ldone, Lunaware, Lunexplored} } ->
			{true, conqueror_info(Lphase, Lmore, Ldone, Lunaware, Lunexplored, State)};
		{more, _To, _From ,{ Vid}} ->
			{true, conqueror_more(Vid, State)};
		{done, _To, _From ,{ Vid}} ->
			{true, conqueror_done(Vid, State)};
		_Other ->
			log_info({"~p do nothing at msg=~p~n",[State#state.id,Event]}),
			{false, State}
	end,	
	
	NextState1 = case (GoFlag == true andalso (length(NextState0#state.unaware) ==0)) of 
		true ->  
			case (queue:len(NextState0#state.answer) > 0) of 
				true ->
					{M1, _Yid} = queue:head(NextState0#state.answer),
					Qanswer = queue:tail(NextState0#state.answer),
					{VVid, _Answer, _Uid} = M1,
					send(VVid,{merge_accept,VVid, State#state.id, {State#state.id } }),
					log_info({"~p[~p] send merge_accept msg to  ~p ~n",[NextState0#state.id,NextState0#state.status, VVid]}),
					Sent1 = NextState0#state.sent + 1,
					NextState0#state{sent = Sent1, answer = Qanswer};
				false ->
					NextState0#state{status = explore}
			end;
		false -> NextState0
	end,

	NextState = NextState1,

	log_info({"~p conqueror Next State = ~p ~n", [State#state.id ,NextState#state.status] },NextState),
	record_state(NextState),
	case ( (NextState#state.status =:= explore) andalso (length(NextState0#state.unaware) ==0)) of
		true -> 
			Nodes = NextState#state.done,
			Round = NextState#state.round + 1,
			%%log_info({"~p tell anyone of node list = ~p ~n", [NextState#state.id ,Nodes] }),
			conquer_notify_node(NextState),
			%%will goto explore
			explore_myself(NextState), 
			log_info({"~p[~p] send explore msg to itself.~n", [NextState#state.id, NextState#state.status ] }),
			Sent = NextState#state.sent + 1,
			%{_Next_state, _NextStateName, NState} = loop_state([], explore , NextState#state{nodes = Nodes}),
			{next_state, NextState#state.status, NextState#state{ids = Nodes, wait = undefined, sent = Sent, round = Round}}; 
		false ->
			{next_state, NextState#state.status, NextState}
	end.

conqueror_release({release, _To, From, M} = Msg, State) ->
	{_Vid, Answer, Uid} = M,
	case ( State#state.id =:= Uid) of
		true ->%% end receiver is me
			%%N = search_release_commit_state( {Vid, Answer, Uid}, State),
			case (Answer =:= merge) of
				true ->
					log_info({"~p[~p] enqueue merge msg=~p. ~n" ,[State#state.id, State#state.status, Msg]}),
					Q = queue:in({M, From},State#state.answer),
					State#state{answer = Q};
				false ->
					log_info({"~p[~p] do nothing at msg=~p~n",[State#state.id, State#state.status, Msg]}),
					State
			end;
		false ->%%forward release msg
			log_info({"~p[~p] forward msg=~p to ~p.~n",[State#state.id, State#state.status, Msg, Uid]}),
			send(Uid,{release, Uid, State#state.id, Msg }),
			State
	end.

explore_myself(State) ->
	send(State#state.id , {explore,State#state.id,State#state.id, {State#state.id} }).

conqueror_more(Vid, State) ->
	case (lists:member(Vid, State#state.unaware)) of
		true ->
			More = lists:umerge([Vid],State#state.more),
			Unaware = lists:delete(Vid,State#state.unaware),
			%%Unexplored = lists:delete(Vid,State#state.unexplored),
			State#state{status = conqueror, unaware = Unaware, more= More};
		false -> State
	end.

conqueror_done(Vid, State) ->
	case (lists:member(Vid, State#state.unaware)) of
		true ->
			Done = lists:umerge([Vid],State#state.done),
			Unaware = lists:delete(Vid,State#state.unaware),
			Unexplored = lists:delete(Vid,State#state.unexplored),
			State#state{status = conqueror, unaware = Unaware, done= Done, unexplored = Unexplored};
		false -> State
	end.
	
conqueror_info(Lphase, Lmore, Ldone, Lunaware, Lunexplored, State) ->
	Unaware1 =  lists:umerge(Lmore, State#state.unaware),
	Unaware2 =  lists:umerge(Ldone, Unaware1),
	Unaware =  lists:umerge(Lunaware, Unaware2),
	%%log_info({"Unaware = ~p~n" ,[Unaware]}),
	Unexplored1 = lists:umerge(Lunexplored, State#state.unexplored),
	Unexplored2 = lists:dropwhile(fun(E) -> lists:member(E, Lmore) end, Unexplored1),
	Unexplored3 = lists:dropwhile(fun(E) -> lists:member(E, Ldone) end, Unexplored2),
	Unexplored  = lists:dropwhile(fun(E) -> lists:member(E, Lunaware) end, Unexplored3),
	log_info({"~p[~p] Unaware = ~p, Unexplored = ~p~n" ,[State#state.id, State#state.status, Unaware, Unexplored]}),
	NN = nn(State#state.phase +1),
	Size1 = length(State#state.more) + length(State#state.done),
	Size = Size1 + length(Unaware),
	Phase = case ((Lphase == State#state.phase) or (Size >= NN) ) of
		true -> 
			State#state.phase+1;
		false -> 
			State#state.phase
	end,
	Sent = case (length(Unaware) >0 ) of 
		true -> 
			lists:foreach(fun(E) -> conquer_node(E, State#state.id) end, Unaware) ,
			State#state.sent + length(Unaware);
		false -> State#state.sent 
	end,

	State#state{status = conqueror, phase =Phase, unaware = Unaware, 
		unexplored = Unexplored, sent = Sent}.

conquer_node(Id, Leader) ->
	log_info({"~p send conquer msg to ~p~n" ,[Leader, Id]}),
	send(Id,{conquer, Id, Leader, {Leader} }).

conquer_notify_node(_State) ->
%	Nodes = State#state.done,
%	lists:foreach(
%		fun(E) -> conquer_node_info(E, State#state.id, Nodes) end, 
%			Nodes) 
ok
	.
	
%conquer_node_info(Id, Leader, Nodes) ->
%	case (Id =:= Leader) of
%		true -> 0;
%		false -> 	send(Id,{notify, Id, Leader, {Nodes} }) end.
		
nn(0) -> 1;
nn(X) -> 2 * nn(X-1).		



%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, State) ->
	ets:delete(?DISCOVERY_NODE, local),
	ets:delete(?DISCOVERY_TABLE, State#state.id),
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
send(Name, Msg) ->
	case global:whereis_name(Name) of	%%erlang:whereis(Name)
		undefined ->
			io:format("~p isn't exist! registered_names=~p~n", [Name, global:registered_names()]),
			false;
		Pid -> 
			Pid ! Msg,
			true
	end.


%ensure_started(Name) ->
%	case erlang:whereis(Name) of
%		undefined ->
%		%	Busid = erlang:whereis(?MODULE),
%		%	Pid = mm:client_start(Ip, ?PORT, Busid),
%		%	register(Name, Pid),
%		%	Pid;
%		undefined;
%		Pid -> Pid
%	end.

%init_table(Node) ->
%	case ets:info(?DISCOVERY_NODE) of
%		undefined -> 
%			_TableNode = ets:new(?DISCOVERY_NODE, [public,set,named_table])
%	end,
%	ets:insert(?DISCOVERY_NODE,{local, Node}),
%
%	case ets:info(?DISCOVERY_TABLE) of
%		undefined -> 
%			_TableState = ets:new(?DISCOVERY_TABLE, [public,set,named_table,{keypos, #state.name}])
%	end.

register_logger(LoggerName) ->
	case global:whereis_name(LoggerName) of	%% erlang:whereis(Name)
		undefined ->
			%%{ok,F} = file:open("ard.log", write),
			_Pid0 = ard_log:start(LoggerName),	%% spawn(fun() -> log_loop(F) end),
			%global:register_name(LoggerName, Pid0),
			register_logger(LoggerName);
		Pid -> 
			case erlang:whereis(?ARD_LOGGER) of 
				undefined ->
					erlang:register(?ARD_LOGGER, Pid),
					true;
				Pid1 ->
					%%io:format("global Pid=~p, local Pid=~p~n", [Pid,Pid1]),
					case (Pid1 =:= Pid) of 
						true -> true;
						false ->
							if ((Pid1 =/= undefined) andalso (Pid1 =/= Pid)) ->
								erlang:unregister(?ARD_LOGGER)
							end,
							erlang:register(?ARD_LOGGER, Pid)
						end,
					true
			end,
			true
	end.

ensure_logger() ->
	Pid = case erlang:whereis(?ARD_LOGGER) of
		undefined ->
			L = get(?ARD_LOGGER),
			Pid0 = global:whereis_name(L) ,
			Pid0;
		Pid1 -> Pid1
	end,
	Pid.
	
record_state(_State) ->
	% ets:insert(?DISCOVERY_TABLE,State)
	ok
	.

log_info(Msg, State) ->
	%Logger = ensure_logger(),
	%io:format("logger pid=~p~n", [Logger]),
	case (get(?LOCAL_NODE) =:= nnode2) of
		true ->
			{Format, Data} = Msg,
			io:format(Format, Data);
		false -> ok
	end,
	global:send(get(?ARD_LOGGER),  {info, now(), self(), list_to_binary(get_msg_info(Msg)), list_to_binary(get_state_info(State))}).
	%Logger ! {info, now(), self(), Msg, State} .


log_info(Msg) ->
	%Logger = ensure_logger(),
	%io:format("logger pid=~p~n", [Logger]),
	case (get(?LOCAL_NODE) =:= nnode2) of
		true ->
			{Format, Data} = Msg,
			io:format(Format, Data);
		false -> ok
	end,
	global:send(get(?ARD_LOGGER),  {info, now(), self(), list_to_binary(get_msg_info(Msg))}).
	%Logger ! {info, now(), self(), Msg}.


log_state_info(State) ->
io:format("id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, nodes=~p, previous_size=~p, ask=~p, sent=~p, recv=~p ~n", 
	[State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
	State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
	State#state.ids, queue:len(State#state.previous), queue:len(State#state.ask),
	State#state.sent, State#state.recv])
	
	.


get_state_info( State)->
	TempList1 = io_lib:format("id = ~p, next = ~p, status=~p,wait = ~p, waiting = ~p, phase = ~p,more = ~p, local = ~p,unaware = ~p,unexplored = ~p, done = ~p, nodes=~p, previous_size=~p, ask=~p, sent=~p, recv=~p ~n", 
	[State#state.id,State#state.next,State#state.status,State#state.wait,State#state.waiting,State#state.phase,
	State#state.more,State#state.local,State#state.unaware,State#state.unexplored,State#state.done,
	State#state.ids, queue:len(State#state.previous), queue:len(State#state.ask),
	State#state.sent, State#state.recv]),
	lists:flatten(TempList1).	%%list_to_atom(

get_log_info(Msg, State)->
	{Format, Data} = Msg,
	TempList0 = io_lib:format(Format, Data),
%	io:format("status = ~p ~n", [State#state.status]),
	TempList1 = get_state_info( State),
	list_to_atom(lists:flatten(TempList0 ++ TempList1)).

get_msg_info(Msg) ->
	{Format, Data} = Msg,
	TempList0 = io_lib:format(Format, Data),
	lists:flatten(TempList0 ).	%%list_to_atom(

readConfig()->
	%% read local record
	{ok, Val} = file:consult("test.dat"),

	Localhost = proplists:get_value(localhost, Val),
	{Name ,_Ip} = Localhost,
%%io:format("Localhost= ~p ~n", [Localhost]),
	L = proplists:get_value(node, Val),
%% io:format("info= ~p ~n", [L]),
	%%Id = {node0,"10.2.128.36"},
	State = #state{status= explore,name = Name, id=Localhost ,next = Localhost, phase =1, 
		more =[Localhost] ,local = L, unaware = [],unexplored =[],done = []},
	 info(State),
	{ok,State}.

info( #state{local = L} = R) ->
	io:format("state = ~p ~n", [R]),
	io:format("local list= ~p ~n", [L]),
	R.
