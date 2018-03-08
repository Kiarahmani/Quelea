http://thelastpickle.cm/blog/2015/10/12/partitioning-cassandra-for-fun-and-timeouts.html

**RUN CCM SERVERS: 
------------------
ccm create QCluster -v 3.7 -n 3 -s --start servers
netstat |grep 9042 --what process is using the port
sudo ifconfig lo0 alias 127.0.0.2 up && sudo ifconfig lo0 alias 127.0.0.3 up

=====================================================================================================================
**PRINTING CONTENTS OF THE CASSANDRA NODES
__________________________________________
while true ; do ccm node1 cqlsh -e "EXPAND ON; SELECT * FROM quelea.bankaccount"> node1.txt; sleep 0.1; done
tail -f node1.txt
while true ; do ccm node2 cqlsh -e "EXPAND ON; SELECT * FROM quelea.bankaccount"> node2.txt; sleep 0.1; done
tail -f node2.txt
while true ; do ccm node3 cqlsh -e "EXPAND ON; SELECT * FROM quelea.bankaccount"> node3.txt; sleep 0.1; done
tail -f node3.txt

multitail -s 3 -ci red node1.txt -ci blue node2.txt -ci yellow node3.txt  
======================================================================================================================
**FINDIG CASSANDRA NODES IP:
*web help: http://thelastpickle.com/blog/2015/10/12/partitioning-cassandra-for-fun-and-timeouts.html
cat ~/.ccm/test/node3/cassandra.pid  ==> --will return the pid of the node 3
sudo lsof -i -P | grep 'PID' 


======================================================================================================================
**CREATE PIPES FOR DELAY SIMULATION:
___________________________________
web help: 
https://mop.koeln/blog/2015/06/01/Limiting-bandwidth-on-Mac-OS-X-yosemite/
http://krypted.com/mac-security/a-cheat-sheet-for-using-pf-in-os-x-lion-and-up/
http://www.hanynet.com/icefloor/index.html
https://spin.atomicobject.com/2016/01/05/simulating-poor-network-connectivity-mac-osx/


*BEGIN:
(cat /etc/pf.conf && echo "dummynet-anchor \"mop\"" && echo "anchor \"mop\"") | sudo pfctl -f -
echo "dummynet in quick proto tcp from any to 127.0.0.2 port 9042 pipe 1" | sudo pfctl -a mop -f -
sudo dnctl pipe 1 config bw 10Kbit/s
-OR:
(cat /etc/pf.conf && echo "dummynet-anchor \"mop\"" && echo "anchor \"mop\"") | sudo pfctl -f - && echo "dummynet in quick proto tcp from any  to {127.0.0.2, 127.0.0.3, 127.0.0.1} port 7000  pipe 1" | sudo pfctl -a mop -f - && sudo dnctl pipe 1 config bw 15Kbit/s delay 1000  && sudo pfctl -e


*END: 
sudo dnctl flush && sudo pfctl -f /etc/pf.conf && sudo pfctl -d


*ADDITIONAL NOTES:
create pipe: dnctl pipe 2 config bw 15Mbit/s delay 1

add rules (following examples) to the sudo vim /etc/pf.conf:
dummynet in quick proto tcp from any  to any port 4000 pipe 1
dummynet in quick proto tcp from any  to any pipe 2

laod the conf file with : sudo pfctl -f /etc/pf.conf 
enable and disable with -e -d 




======================================================================================================================
**RUN MULTI-SERVER SETTING LOCALLY:
___________________________________
1]
./BankAccount_CC --kind Drop                            ==> clears the previously defined keyspace
make BROKER=-DLBB BankAccount_CC                        ==> compiles the test, DLBB part specifies 
					   		    the distributed setting of servers
./BankAccount_CC --kind Create --brokerAddr 127.0.0.1   ==> creates the keyspace according to the broker address

*OR:
./BankAccount_CC --kind Drop && make clean &&  make BROKER=-DLBB BankAccount_CC  && ./BankAccount_CC --kind Create --brokerAddr 127.0.0.1

2]
*START THE BROKER:
./BankAccount_CC --kind Broker --brokerAddr 127.0.0.1

3]
*START THE SERVER:
./BankAccount_CC --kind Server --rtsArgs "-N2" --brokerAddr 127.0.0.1

4]
*START THE CLIENT:
./BankAccount_CC --kind Client --rtsArgs "-N2" --numThreads 1 --brokerAddr 127.0.0.1 --numRounds 1 --measureLatency


-- more recent commands -- 3 screen setting
----------------------
**SERVER: 
./BankAccount_CC --kind Drop && ./BankAccount_CC --kind Create --brokerAddr 127.0.0.1 && ./BankAccount_CC --kind Server --rtsArgs "-N2" --brokerAddr 127.0.0.1

**COMPILE:
make clean && make BROKER=-DLBB BankAccount_CC


======================================================================================================================
** SENDING COMMANDS TO TMUX PANES
_____________________________________________________________
Prompt>> session=Dashboard
Prompt>> window=${session}:0
Prompt>> pane=${window}.4
Prompt>> tmux send-keys -t "$pane" C-z 'ls' Enter

======================================================================================================================
** NOTES ON MODIFIED CODE FOR RUNNING MULTIPLE SHIMS LOCALLY:
_____________________________________________________________

1] In the main run function at "Server" Case: instead of callin "runShimNode" function, fork 2 new processes and call the function twice. 
The module must wait, because of it dies, the child processes will die also (we did not have this problem before, because shim calls were normal function call and we had to wait for it anyway, and since shim runs forever we would wait forever).     [**TO-DO**] : I fixed the problem by putting a finite delay after forking the shims. this must be changed to unlimited wait. 
let ns1 = mkNameService (Frontend $ "tcp://" ++ broker ++ ":" ++ show fePort)
                         (Backend  $ "tcp://" ++ broker ++ ":" ++ show bePort) "localhost" 5560

let ns2 = mkNameService (Frontend $ "tcp://" ++ broker ++ ":" ++ show fePort)
			 (Backend  $ "tcp://" ++ broker ++ ":" ++ show bePort) "localhost" 5561
.
.
Server -> do
	tid1 <- forkIO $ runShimNode dtLib [("127.0.0.1","9042")] keyspace ns1 1
        tid2 <- forkIO $ runShimNode dtLib [("127.0.0.2","9042")] keyspace ns2 2
	threadDelay 200000000
	putStrLn "Server is Shut Down"



2] In the Broker, mkNameService function is defined: 
meService :: Frontend -> Backend -> String -> Int -> NameService
The String (ip) and the Int (port) do not matter: since we don't want session stickiness in the Broker.

======================================================================================================================
** NOTES ON HANDLING ghc: panic! (the 'impossible' happened) ERROR
_____________________________________________________________
- solution: just manually delete everything but the sources and compile it from the scratch: rm *.hi && rm *.o && rm *.*d*

** NOTES ON HANDLING ghc:     lexical error at character 'i' ERROR
_____________________________________________________________
- solution: add this to the beginning of the files: {-# LANGUAGE CPP #-}

** NOTES ON HANDLING ghc:    Illegal datatype context (use DatatypeContexts): ERROR
_____________________________________________________________
- solution: add this to the beginning of the files:  {-# LANGUAGE DatatypeContexts #-}

** NOTES ON HANDLING ghc:   BankAccount_CC.hs:87:6: Not in scope: â<>â Perhaps you meant one of these:
_____________________________________________________________
- solution: import Data.Monoid
















