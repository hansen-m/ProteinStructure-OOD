#!/bin/bash

echo "IN EPILOG" >> output_location/epi.log

##SYSTEM Clean up
#Wipe dead sessions
screen -wipe

#Wipe sessions for this job
screen -S some_name_variable -X quit

#write screen to log
screen -ls >> output_location/epi.log

#Wipe tmux sessions
tmux kill-session

#write tmux to log
tmux ls >> output_location/epi.log

#RISE Clean up
echo "manually deleting..." >> output_location/epi.log
/usr/bin/rm -v ~/scratch/.screen/run/*.some_name_variable >> output_location/epi.log
myuid=$(id -u $USER)
rm -rf /tmp/tmux-${myuid} >> output_location/epi.log 
echo "done..." >> output_location/epi.log
 
