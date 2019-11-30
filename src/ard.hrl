-define(ARD_LOGGER, ard_logger).
-define(ARD_MONITOR, ard_monitor).
-define(LOCAL_NODE, local_node_name).
%-define(DISCOVERY_STATE_RECORD, discovery_state_record).

-define(DISCOVERY_NODE, discovery_node).
-define(DISCOVERY_TABLE, discovery_state).

-define(ARD_ROUND, ard_round).
-define(ARD_SEND, ard_send).
-define(ARD_RECEIVE, ard_receive).

%% A locally registered name
-type name() :: atom().

-type id() ::atom().
-type ids() :: [ id()].
-type fifo() :: gb_tree().

-type nodeparm() :: {integer(), id(), ids() }.
-type nodeparms() ::[nodeparm()].
-record(parm, {
	max			::integer(),
	nodes	=[]	::nodeparms()
	}).

-type ringitem()	:: { id(), integer(),  integer()}.
-type ring()		::[ringitem()].
-type ringkey()		:: {integer(), id()}.
-type rings()		::[ringkey()].
-record(ring,{
	key		::ringkey(),
	id      ::id(),
	phase	::integer(),
	pub		::integer()
}).

-record(monitor, {
	id			:: id(),	%%monitor name
	target		:: ringkey(),
	targetid	:: id(),
	father		:: ringkey(),
	fatherid	:: id(),
	ref,
	status
}).

-type status() :: 'explore' | 'wait' | 'conqueror' | 'inactive' | 'conquered' |
                  'passive'.
-record(state, {
	leader = none	     :: 'none' | pid(),
    name                :: name(),
    leadernode = none   :: node(),
 	status	:: status(),
	id      ::id(),
	phase	::integer(),
	round	::integer(),	%% search round for ard
	waiting	::boolean(),
	wait	::id(),
	next	::id(),
	ids		::ids(),
	local		= []  	::ids(),
	unaware		= []	::ids(),
	unexplored	= []	::ids(),
	done		= []	::ids(),
	more		= []	::ids(),
	previous		::queue(),
	sent		= 0	::integer(),%% send msg counter
	recv		= 0	::integer(),%% receiver msg counter
	ask				::queue(),%% search msg queue
	answer			::queue(),%% release msg queue
	phset		= []		::dict(),
	orderset	= [],		%%::gb_sets() %% use for decide the next leader
	mview		= []	::ring(),	%% MemberView 
	monitor		::id(),	%%
	closestid	::ringkey(),
	faults		= []	::rings()
    }).