# Asynchronous Resource Discovery

A Scalable and Dynamic Network Topology and Service

Part Ⅰ	Introduction</br>
Origin</br>
We need a scalable technique in distributed message system, it may be summarized as follows </br>
Self-Organization</br>
The resulting network is self-constructed  and decentralized</br>
Dynamic</br>
Each node can join or leave the network  at any time</br>
Robustness</br>
Dealing with node failure and fault-tolerance</br>
</br>
All roads  lead to Rome?</br>
Paxos / Zab</br>
A family of protocols for solving distributed consensus</br>
Totem</br>
Single-ring ordering  and membership protocol</br>
Leader election</br>
A series of classic distributed algorithms </br>
Resource discovery</br>
A series of algorithms about how to discover each other</br>
Gossip</br>
A class of algorithms are built upon a gossip or rumor style unreliable, asynchronous information exchange protocol</br>
</br>

Paxos</br>
Quorums principle - 2N+1</br>
Two-phase protocol agreed value</br>
Dueling proposers and leadership</br>
Zab – Atomic broadcast protocol</br>
Stricter ordering guarantee than Paxos</br>
The main difference is that Zab is designed for primary-backup system, like Zookeeper, rather than for state machine replication.</br>

Totem</br>
Virtual synchrony</br>
Group membership</br>
Group broadcast</br>
Total order is guaranteed</br>
Protocol</br>
Total-ordering protocol</br>
Agreed Order</br>
Safe Order</br>
Membership protocol</br>
Recovery protocol</br>

Simple and Lightweight Algorithms</br>
Leader election</br>
LCR algorithm – 〖Ο(𝑛^2 )〗^</br>
HS algorithm improved it - Ο(𝑛 log⁡𝑛 )</br>
Bully algorithm - Ο(𝑛^2 )</br>
Resource discovery</br>
The common first step in distributed system</br>
Who on the network wants to cooperate with me?</br>
Gossip algorithms</br>
This is an amazing algorithm!</br>
reliable communication is not assumed</br>
robust against node failures and changes in topology</br>
And it seems very simple</br>
Just exchange information between each other periodically and randomly</br>

Performance</br>
How to measure it?</br>
Time complexity</br>
The number of rounds until all the required outputs are produced, or until the processes all halt</br>
Message complexity</br>
The total number of messages have been sent throughout the execution</br>
Pointer complexity</br>
The number of bits in the message</br>
</br>
Problem Definition</br>
</br>
Asynchronous  resource discovery</br>
Exactly one node in every weakly connected component is designated as leader</br>
The leader node knows the ids of all the nodes in its component</br>
All nodes know the id of their leader</br>
</br>
Gossip-based membership</br>
An inexpensive membership management </br>
A small and partial, but more accurate view of membership rather than whole view of membership</br>
The result is a decentralized topology with good connectivity and robustness, and low diameter</br>
</br>
Resource Discovery</br>
</br>
Previous Work</br>
</br>
Flooding algorithm :  Ω(d 𝑖𝑛𝑖𝑡𝑖𝑎𝑖𝑙·m 𝑖𝑛𝑖𝑡𝑖𝑎𝑖𝑙)</br>
A machine is initially configured to have a fixed set of neighbors machines, and direct communication is only allowed with machines in this set
</br></br>
Swamping algorithm:  Ω(n²)</br>
It is similar to flooding, but it may swap with all current neighbors</br>
</br>
Random Pointer Jump:  (num. rounds) · n</br>
One kind of “pull style” gossiping algorithm</br>
</br>
Name-Dropper:  O(n log² n)</br>
One kind of “push style” gossiping algorithm</br>
</br>
</br>
Generic Algorithm</br>
</br>
Union-Find</br>
find( A ) - finds what set A belongs to</br>
union( A, B ) - merge A's set with B's set</br>
union by rank</br>
path compression</br>
Basic algorithm</br>
Find an unexplored node u</br>
Reach the current leader, l, of node u</br>
Merge l into v</br>
Inform all of l’s nodes of their new leader</br>
</br>
Asynchronous Resource Discovery</br>
</br>
Each node begins in state ‘explore’ and during its execution may change its state to ‘wait’ and then
‘conqueror’, ‘passive’, ‘conquered’ or ‘inactive’. A diagram with all the state transition is shown in Figure 1.
We will call a node leader if its state is not ‘conquered’ or ‘inactive’ or ‘passive’. Thus the state of a leader
node is ‘explore’ or ‘wait’ or ‘conqueror’. Each node maintains five sets of ids: local, done, more, unaware,
and unexplored, a FIFO queue previous, two id pointers: id, and next, and one integer: phase. The id
field holds the node’s unique id. Initially local holds the set of ids the node initially knows. The set more
initially contains the element {id}, next = id, phase = 1, the sets done, unaware, unexplored, and the
queue previous are empty.</br>
</br>
</br>
Complexity</br>
</br>
Generic Algorithm ⟶ Ο(𝑛 log⁡𝑛 )</br>
Bounded, and the Ad-hoc algorithms ⟶ Ο(𝑛𝛼(𝑛,𝑛))</br>
</br>
‘query’ and ‘query reply’ messages ⟶ at most 4𝑛</br>
‘search’ and ‘release’ messages ⟶ Ο(𝑛𝛼(𝑛,𝑛))</br>
‘merge accept’, ‘merge fail’, and ‘info’ messages ⟶ at most 2𝑛</br>
‘conquer’, ‘more/done’ messages ⟶ at most 2𝑛∙log⁡𝑛 in the Generic Algorithm, and at most 2𝑛 in the Bounded model.</br>
