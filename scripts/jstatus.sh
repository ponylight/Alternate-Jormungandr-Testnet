#!/bin/bash

# Author: Redoracle
# Pool: Stakelovelace.io
# TG: @redoracle
#
# To keep logs of this WatchDog tool please use it as described below.
# Usage: ./jstatus.sh | tee -a /tmp/jstatus.log
#
#
# How the fork/stuck check works:
# The script will retrieve  the last block hash elaborated by the node (jcli) and query the ITN IOHK eplorer to very the block hash  
# In addition the node BlockHihgt is updated on PoolTool.io and simultaneosly using the return value and second reference before 
# starting evaluating the Recovery Restart function.
#
# When exported the MY_POOL_ID variable, your pool's stats (rewards and stake) will show up on the screen 
#
# Do not forget to customize the RECOVERY_RESTART() function in order to implement your own recovery procedure.
#
# Featuers:
#              - PoolTool sendtips.sh functions integrated if ENV vars are declared.  
#              - Fork/Sanity Check (by simultaneolsy checking PoolTool and ShellyExplorer)
#              - Node Stuck 
#                       1) by setting max block heghit difference: "Block_diff" (default 50)
#                       2) by setting FLATCYCLE: period which will be considered before triggering RECOVERY RESTART procedure
#              - IM settings and samples for Gotify and Telegram (thanks to @Gufmar)
#              - Jormugandr Storage Auto Backup (only when the node is healthy)
#
#
# Notes: the msg " HASH NOT IN ESPLORER" could appear in 3 different situations:
#
#           - 1) The HAST is not yet in Shelly Exporer, not in sync (usually after few minutes the alert reset because the scripts 
#                retries and finds it)
#           - 2) Shelly Exporer Webserver is not responding (usually after few minutes the alert reset because the scripts retries 
#                and finds it)
#           - 3) The HAST is not yet in Shelly Exporer and never will be because your node is on a fork, for making sure we do not 
#                get False Positive we also check PoolTool - Very Useful Tool -.
#
#   
#
# Disclaimers:
#               1)   -->!!    USE THIS SCRIPT AT YOUR OWN RISK. IT IS YOUR OWN RESPONSABILITY TO MONITOR YOUR NODE!    !!<--
#               2)                                  DO YOUR OWN TUNING --> 
#       Each node might need proper fine tunes of the Global variable declared under the "## Configuration Parameters" section.
#               3)   -->!!    USE THIS SCRIPT AT YOUR OWN RISK. IT IS YOUR OWN RESPONSABILITY TO MONITOR YOUR NODE!    !!<--
#
# Contributors: @Cardano_Staking_Pools_Alliance SPAI
#
## Shelly Explorer:
# https://explorer.incentivized-testnet.iohkdev.io/explorer/
# 
## Configuration Parameters 
#
## Rewards directory dump
export JORMUNGANDR_REWARD_DUMP_DIRECTORY=/datak/pool/Stakelovelace/Rewards

## ITN Genesis
GENESISHASH="8e4d2a343f3dcf9330ad9035b3e8d168e6728904262f2c434a4f8f934ec7b676"

## PoolTool Configuration
THIS_GENESIS="8e4d2a343f3dcf93"   # We only actually look at the first 7 characters of the ITN genesis

#export MY_POOL_ID="YOUR-POOL-ID"   # Your Pool public IP
#export MY_USER_ID="YOUR-POOLTOOL-ID"  # on pooltool website get this from your account profile page
MY_USER_ID="f4700f4f-57c9-4394-afb4-60535fa7add6"  # on pooltool website get this from your account profile page

## BACKUP
#JTMP="/datak/jormungandr-storage";          # Jormugandr Storage PATH (must match your storage settings PATH in your node-config.yaml)
                                            # If set it will enable automatic backup 
JTMPB="/datak/jormungandr-storage_backup"   # Backup destination

BACKUPCYCLES=10         # Backup window  FREQ x BACKUPCYCLES = trigger backup procedure

## Telegram Message API 
#
# 1) Talk with @BotFather and a create a new bot with the command "/newbot" follow the procedure and keep notes of your BotToken
# 2) Then invite @Markdown @RawDataBot and also get the "chat_id"
#    This is an individual chat-ID between the bot and this TG-user the bot is allowed to respond, when the user send a first message.
# 3) write some messages within your botchat group and then run the following command:
# 4) curl -s https://api.telegram.org/bot${TG_BotToken}/getUpdates | jq .
#    the returned JSON contains the chat-ID from the last message the bot received.
# 4b) or get directly the chat_id:
#    curl -s https://api.telegram.org/bot${TG_BotToken}/getUpdates | jq . | grep -A1 chat | grep -m 1 id | awk '{print $2}' | cut -d "," -f1
## TG Settings:
#TG_BotToken="xxxxxxxxx:xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxx"
#TG_ChatId="xxxxxxxxx"
#TG_URL="https://api.telegram.org/bot${TG_BotToken}/sendMessage?chat_id=${TG_ChatId}&parse_mode=Markdown"

ALERT_MINIMUM=2      # minimum test loops pefore pager alert

## Cycles Time frequency in seconds:
#
FREQ=60                 # Normal Operation Refresh Frequency in seconds

FORK_FREQ=120           # Forck Check - Warning Mode Refresh Frequency in seconds between checks. after 13 consecutive failed attempts to check 
                        # the last block hash the script will try to do the recovery steps if any. See RECOVERY_RESTART().

RECOVERY_CYCLES=13      # How many times will the test cycle (Explorer Website check  + PoolTool check) with consecutive errors
                        # the script will try to do the recovery steps if any. See RECOVERY_RESTART()

FLATCYCLES=2            # Every Cycle FREQ lastblockheight will be checked and if it stays the same for FLATCYCLES times, 
                        # than the Monster will be Unleashed!  

## Block difference checks for stucked nodes
#
Block_diff=10  # Block_diff is a isolated check which alone will trigger 1 of 13 warning alerts befor calling the function RESTART_RECOVERY - Explorer will be out of the checks chain
Block_delay=10  # Block_delay is part of the double check algorithm with the comparison of the shellyExplorer (the combination of 1 Hash not found and Lastblock heigh < 20 blocks trigger 1 of 13 consecutives alerts before triggering the recovery)


## Log PATH
#
LOG_DIRECTORY="/tmp";
LEADERS="$LOG_DIRECTORY/leaders_logs.log";   # PATH of the temporary leaders logs from jcli for collecting stats


## Clolors palette
#
BOLD="\e[1;37m"; GREEN="\e[1;32m"; RED="\e[1;31m"; ORANGE="\e[33;5m"; NC="\e[0m"; CYAN="\e[0;36m"; LGRAY1="\e[1;37m"; LGRAY="\e[2;37m"; BHEIGHT="\e[1;32m";
REW="\e[1;93m"; POOLT="\e[1;44m";

## Main Init
#
shopt -s expand_aliases
alias CLI="$(which jcli) rest v0"
FIRSTSTART="1";

clear;
echo -e "\\t\\t$BOLD- jstatus WatchDog -$NC";
echo -e "\\t\\t$LGRAY1   v1.1.6   2020 $NC\\n\\n";
echo -e "\\t\\t$LGRAY1    Loading...  $NC\\n\\n";

[ -f CLI ] && [ -f jcli ] && CLI="./jcli"
[ -z ${JORMUNGANDR_RESTAPI_URL} ] && echo -e "[ERROR] - you must set the shell variable \$JORMUNGANDR_RESTAPI_URL, \\ncheck your node config for the rest: listen_address to identify the URL, \\neg: export JORMUNGANDR_RESTAPI_URL=http://127.0.0.1:3101/api" && exit 1
[ -z ${MY_USER_ID} ] && echo -e "[WARN] - PoolTool parameters not set, therefore no tip submissions than. \\neg: export MY_POOL_ID=xxxxxxxxxxx \neg: export MY_USER_ID=xxxx-xxxxx-xx" && PoolToolHeight="00000";

## Functions
POOLTOOL_S()
{
[ -z ${MY_USER_ID} ] && echo -e "[WARN] - PoolTool parameters not set \\neg: export MY_POOL_ID=xxxxxxxxxxx \neg: export MY_USER_ID=xxxx-xxxxx-xx" && PoolToolHeight="00000";

if [[ $PoolToolHeight == "00000" ]];
then
    BHEIGHT="\e[1;31m";
    PTSUBMISSION=" ";
elif [ "$lastBlockHeight" != "" ]; 
    then
    PoolToolURL="https://api.pooltool.io/v0/sharemytip?poolid=$MY_POOL_ID&userid=$MY_USER_ID&genesispref=$THIS_GENESIS&mytip=$lastBlockHeight&lasthash=$lastBlockHash&lastpool=$lastPoolID";
    PoolToolHeight=$(curl -s -G $PoolToolURL | grep pooltool | cut -d "\"" -f 6);
    PTSUBMISSION=" Sub:$PoolToolHeight";
fi
}

POOLTOOL()
{
sleep 1;
PoolToolStats2=$(curl -s -o $LOG_DIRECTORY/pooltool_stats.json https://pooltool.s3-us-west-2.amazonaws.com/stats/stats.json);
PoolT_min=$(jq .min $LOG_DIRECTORY/pooltool_stats.json);
PoolT_syncd=$(jq .syncd $LOG_DIRECTORY/pooltool_stats.json );
PoolT_sample=$(jq .samples $LOG_DIRECTORY/pooltool_stats.json);
PoolT_max=$(jq .majoritymax $LOG_DIRECTORY/pooltool_stats.json);
PoolT_sec=$(jq .distribution $LOG_DIRECTORY/pooltool_stats.json | grep "\"" | sort -nr -t ',' -k8 | grep -v $PoolT_max |head -n 1 |cut -d "\"" -f 2);

POOLTOOLSTAS="PoolTHeight:\\t$POOLT-> 1st:$PoolT_max - 2nd:$PoolT_sec - ($PoolT_syncd/$PoolT_sample) <-$NC";
if [ "$lastBlockHeight" -lt $(($PoolT_max - $Block_delay)) ]; 
then
    BHEIGHT="\e[1;31m";
else
    BHEIGHT="\e[1;32m";
fi
sleep 1;
}

INIT_JSTATS()
{
        DATE=$(date);
        ORA=$(date +"%H");
        HOSTN=$(hostname);
        DAY=$(date +"%d");
        TMPF="$LOG_DIRECTORY/stats.json";
        QUERY=$(CLI  node stats get --output-format json > $TMPF);
        lastBlockDateSlot=$(jq -r .lastBlockDate $TMPF | cut -d "." -f 1);
        lastBlockDateSlotFull=$(jq -r .lastBlockDate $TMPF )
        blockRecvCnt=$(jq -r .blockRecvCnt $TMPF);
        lastBlockHeight=$(jq -r .lastBlockHeight $TMPF);
        uptime=$(jq -r .uptime $TMPF);
        lastBlockTx=$(jq -r .lastBlockTx $TMPF);
        txRecvCnt=$(jq -r .txRecvCnt $TMPF);
        nodesEstablished=$(CLI network stats get --output-format json | jq '. | length');
        Quarantined=$(curl -s $JORMUNGANDR_RESTAPI_URL/v0/network/p2p/quarantined 2>/dev/null  | jq '.' | grep addr | sort | uniq | wc -l)
        Quarantined_non_public=$(curl -s $JORMUNGANDR_RESTAPI_URL/v0/network/p2p/non_public 2>/dev/null  | jq '.' | grep addr | sort | uniq | wc -l)
        LAST_HASH=$(jq -r .lastBlockHash $TMPF);
        lastBlockHash=$LAST_HASH;
        lastPoolID=$(CLI block ${LAST_HASH} get | cut -c169-232)

        if [ $MY_POOL_ID ]; 
            then
            LAST_EPOCH_POOL=$(CLI stake-pool get $MY_POOL_ID > $LOG_DIRECTORY/$lastBlockDateSlot.poolstats_01 );    
            LAST_EPOCH_POOL_REWARDS=$( grep value_taxed $LOG_DIRECTORY/$lastBlockDateSlot.poolstats_01 | awk '{print $2}' | awk '{print $1/1000000}' | cut -d "." -f 1 );
            LAST_EPOCH_POOL_DEL_REWARDS=$( grep value_for_stakers $LOG_DIRECTORY/$lastBlockDateSlot.poolstats_01 | awk '{print $2}' | awk '{print $1/1000000}' | cut -d "." -f 1 );
            POOL_DELEGATED_STAKEQ=$( grep total_stake $LOG_DIRECTORY/$lastBlockDateSlot.poolstats_01 | awk '{print $2}' | awk '{print $1/1000000000}' | cut -d "." -f 1 );
            POOL_DELEGATED_STAKE="Stake(K):\\t$REW$POOL_DELEGATED_STAKEQ$NC"
            LASTREWARDS="LastRewards:\\t$REW$LAST_EPOCH_POOL_REWARDS$NC";
            POOLINFO="-> $POOL_DELEGATED_STAKE\\t- $LASTREWARDS"
            else
            POOLINFO="";
        fi
}

PRINT_SCREEN()
{
                LEADERS_QUERY=$(CLI leaders logs get > $LEADERS);
                SLOTS=$(grep -B2 Pending $LEADERS | grep -A1 "scheduled_at_date:" | grep -A1 "$lastBlockDateSlot\." | grep scheduled_at_time | wc -l);
                NEXT_SLOTS=$(grep -A 1 scheduled_at_time  $LEADERS | grep $DAY'T'$ORA | wc -l);
                NEXT_SLOTS_LIST=$(grep scheduled_at_time  $LEADERS | grep $DAY'T'$ORA | awk '{print $2}'| cut -d "T" -f 2|cut -d "+" -f 1| sort);
                BLOCKS_MADE1=$(grep -A1 -B3 Block $LEADERS | grep -A5 "scheduled_at_date:" | grep -A4 "$lastBlockDateSlot\." | grep block | cut -d ":" -f 2 >> $LOG_DIRECTORY/$lastBlockDateSlot.leaders_logs.1 );
                BLOCKS_MADE2=$(cat $LOG_DIRECTORY/$lastBlockDateSlot.leaders_logs.1 | sort -nr | uniq  > $LOG_DIRECTORY/$lastBlockDateSlot.leaders_logs);
                LAST_BLOCKH=$(cat $LOG_DIRECTORY/$lastBlockDateSlot.leaders_logs | tail -n 1 | awk '{ print $1 }');
                BLOCKS_MADE=$(cat $LOG_DIRECTORY/$lastBlockDateSlot.leaders_logs | wc -l );
                BLOCKS_ON_CHAIN=$(echo "/ociao");
                watch_node=$(netstat -anl  | grep tcp | grep EST |  awk '{ print $5 }' | cut -d ':' -f 1 | sort | uniq | wc -l);
                BLOCKS_REJECTED1=$(grep -B3 Rejected $LEADERS | grep -A1 "$lastBlockDateSlot\."| grep scheduled_at_time >> $LOG_DIRECTORY/$lastBlockDateSlot.leaders_rej_logs);
                BLOCKS_REJECTED2=$(cat $LOG_DIRECTORY/$lastBlockDateSlot.leaders_rej_logs| sort -nr | uniq > $LOG_DIRECTORY/$lastBlockDateSlot.leaders_rej_uniq_logs);
                BLOCKS_REJECTED=$(cat $LOG_DIRECTORY/$lastBlockDateSlot.leaders_rej_uniq_logs | wc -l );
                REASON_REJECTED=$(grep -A1 Rejected $LEADERS);
                clear;
                echo -e "-> $DATE \\t $STATUS";
                echo -e "-> HOST:$BOLD$HOSTN$NC   Epoch:$BOLD$lastBlockDateSlotFull$NC   Uptime:$BOLD$uptime$NC  ";
                echo -e " ";
                echo -e "-> RecvCnt:\\t$LGRAY$blockRecvCnt$NC \\t- BlockHeight:\\t$BHEIGHT-> $lastBlockHeight <-$PTSUBMISSION$NC";
                echo -e "-> BlockTx:\\t$LGRAY$lastBlockTx$NC \\t- $POOLTOOLSTAS";
                echo -e "-> txRecvCnt:\\t$LGRAY$txRecvCnt$NC \\t- Quarantined:\\t$ORANGE$Quarantined$NC"       ;
                echo -e "-> UniqIP:\\t$CYAN$watch_node$NC \\t- Established:\\t$BOLD$nodesEstablished$NC";
                echo -e "$POOLINFO";
                echo -e " ";
                echo -e "-> Last Hash:\\n$LAST_HASH";
                echo -e "-> Made:$GREEN$BLOCKS_MADE $NC- Rejected:$RED$BLOCKS_REJECTED$NC - Slots:$ORANGE$SLOTS$NC - Planned(b/h):$BOLD$NEXT_SLOTS$NC";
                echo -e "$BOLD$NEXT_SLOTS_LIST$NC";
                echo -e ":\\n$ORANGE$REASON_REJECTED$NC\\n";
}


RECOVERY_RESTART()
{
    echo -e "\\t\\t\\t\\t $RED--> We're ... Restarting! <--$NC";
    #AUE=$(curl -s -X POST "http://172.13.0.4/message?token=Ap59j48LrTeyvQx" -F "title=$HOSTN Fork Restart" -F "message=Restarting!!" -F "priority=$TRY");
    #TGAUE=$(curl -s -X POST $TG_URL -d text="$HOSTN Recovery Restart %0AFLATLINERSCOUNTER:$FLATLINERSCOUNTER %0ATRY:$TRY %0AHASH: $LAST_HASH %0APOOLTHEIGHT: $PoolT_max %0APOOLINFO DS: $POOL_DELEGATED_STAKEQ LR: $LAST_EPOCH_POOL_REWARDS");
    #jshutdown=$(CLI shutdown get);
    #sleep 2;
    #jshutdown2=$(ps max | grep jorm | grep config | awk '{print $1}');
    #jshutdown3=$(kill -9 $jshutdown2 );
    #CLEANDB=$(rm -rf $JTMP);
    sleep 1;
    #RECOVERSTORAGE=$(cp -rf $JTMPB $JTMP);
    #RECOVERY=$(echo -e "\\t\\t $RED--> Recovery in course please wait around 10 minutes$NC");
    #GHASH=$(cat /datak/genesis-hash.txt); 
    #START_JORGP=$(/root/jormungandr/jormungandr --config /datak/node-config.yaml --secret /datak/pool/YOUPOOL/secret.yaml --genesis-block-hash $GHASH &> $LOG_DIRECTORY/$HOSTN.log &);
}

PAGER()
{
    echo -e "\\n \\t\\t\\t$RED-->  Pager Warning Alert sent!   <--$NC";
    ##Telegram
    #TGAUE=$(curl -s -X POST $TG_URL -d text="$HOSTN Potential Fork %0ATRY:$TRY FLATLINERSCOUNTER:$FLATLINERSCOUNTER %0AHASH:[$LAST_HASH](https://explorer.incentivized-testnet.iohkdev.io/tx/$LAST_HASH) %0APOOLTHEIGHT: $PoolT_max %0APOOLINFO DS: $POOL_DELEGATED_STAKEQ LR: $LAST_EPOCH_POOL_REWARDS");
    ##Gotify
    #AUE=$(curl -s -X POST "http://172.13.0.4/message?token=Ap59j48LrTeyvQx" -F "title=$HOSTN Potential Fork" -F "message=TRY:$TRY -> HASH:$LAST_HASH PTH:$PoolT_max DS:$POOL_DELEGATED_STAKEQ LR:$LAST_EPOCH_POOL_REWARDS" -F "priority=$TRY");
}

PAGER_BLOCK_MADE()
{
    if [ "$FIRSTSTART" -eq "1" ]; then
        FIRSTSTART=0;
    else
        echo -e "\\n \\t\\t\\t$REW-->  New block Made!  <--$NC";
        ##Telegram
        #curl -s -X POST $TG_URL -d text="$HOSTN Block just Made N: $BLOCKS_MADE %0APOOLTHEIGHT: $PoolT_max %0APOOLINFO: %0ADS: $POOL_DELEGATED_STAKEQ LR: $LAST_EPOCH_POOL_DEL_REWARDS %0ABlock:[$LAST_BLOCKH](https://explorer.incentivized-testnet.iohkdev.io/block/$LAST_BLOCKH)" > /tmp/lasttx.json ;
        #AUE=$(curl -s -X POST "http://172.13.0.4/message?token=Ap59j48LrTeyvQx" -F "title=$HOSTN Block just Made" -F "message=$HOSTN Block just Made N:$BLOCKS_MADE PTH:$PoolT_max DS:$POOL_DELEGATED_STAKEQ LR:$LAST_EPOCH_POOL_REWARDS" -F "priority=5");
    fi

}

PAGER_BLOCK_REJ()
{
        echo -e "\\n \\t\\t\\t$RED-->  New block Rejected!  <--$NC";
        ##Telegram
        #TGAUE=$(curl -s -X POST $TG_URL -d text="$HOSTN Block just Rejected N:$BLOCKS_REJECTED R:$REASON_REJECTED %0APOOLTHEIGHT: $PoolT_max %0APOOLINFO DS: $POOL_DELEGATED_STAKEQ LR: $LAST_EPOCH_POOL_REWARDS");
        ##Gotify
        #AUE=$(curl -s -X POST "http://172.13.0.4/message?token=xxxx" -F "title=HOSTN Block just Rejected" -F "message=$HOSTN Block just Rejected Reason:$REASON_REJECTED POOLTHEIGHT: $PoolT_max" -F "priority=8");
}

EVAL_PAGE_BLOCK()
{
if [ $BLOCKS_REJECTED -gt $BLOCKS_REJECTED_TMP ]; then
    PAGER_BLOCK_REJ;
    BLOCKS_REJECTED_TMP="$BLOCKS_REJECTED";
else
    BLOCKS_REJECTED_TMP="$BLOCKS_REJECTED";
fi
    
if [ $BLOCKS_MADE -gt $BLOCKS_MADE_TMP ]; then
    PAGER_BLOCK_MADE;
    BLOCKS_MADE_TMP="$BLOCKS_MADE";
else
    BLOCKS_MADE_TMP="$BLOCKS_MADE";
fi
}

EXPLORER_CHECK()
{
curl -s 'https://explorer.incentivized-testnet.iohkdev.io/explorer/graphql' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:71.0) Gecko/20100101 Firefox/71.0' -H 'Accept: */*' -H 'Accept-Language: en-US,en;q=0.5' --compressed -H "Referer: https://shelleyexplorer.cardano.org/en/block/$LAST_HASH/" -H 'Content-Type: application/json' -H 'Origin: https://shelleyexplorer.cardano.org' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'TE: Trailers' --data "{\"query\":\"\n    query {\n      block (id: \\\"$LAST_HASH\\\") {\n        id\n      }\n    }\n  \"}" | grep "\"block\":{\"id\":\"$LAST_HASH\"" &> $LOG_DIRECTORY/explorer.check.log;
RESU=$?;

if [ $RESU -gt 0 ]; then
    STATUS="$RED- HASH NOT IN EPLORER! -$NC"
elif [ $FLATLINERSCOUNTER -gt 0 ]; then
    STATUS="$RED- FLATLINER DETECTED! n:$FLATLINERSCOUNTER -$NC"
elif [ $FLATLINERSCOUNTER -gt 0 ] && [ $RESU -gt 0 ]; then
    STATUS="$RED- HASH NOT IN EPLORER and FLATLINER DETECTED n:$FLATLINERSCOUNTER -$NC"
else
    STATUS="$GREEN - Looking Good! - $NC"
fi
}

FLATLINERS_CHECK()
{
    lastBlockHeight=$(jq -r .lastBlockHeight $TMPF);

    if [ $lastBlockHeight -eq $FLATLINERS ];
        then
            let FLATLINERSCOUNTER+=1;
        else 
            FLATLINERS="$lastBlockHeight";
            FLATLINERSCOUNTER=0;
    fi
}

# Customize it with your own backup procedure
STORAGE_BACKUP()
{
if [ $JTMP ] && [ "$BACKUP" -eq "0" ]; then
        BACKUP_RUN_CLEAN=$(rm -rf $JTMPB);
        sleep 1;
        BACKUP_RUN_COPY=$(cp -rf $JTMP $JTMPB);
        let BACKUP+=1;
        # echo "Backup done!";
    elif  [ "$BACKUP" -gt "$BACKUPCYCLES" ]; then
        BACKUP=0;
        # echo "Backup to be created next cycle";
    else
        let BACKUP+=1;
        # echo "No backup activity";
fi
}

## Reset Variables
BLOCKS_MADE_TMP=0;
BLOCKS_REJECTED_TMP=0;
FLATLINERS=0;
FLATLINERSCOUNTER=0;
TRY=0;
BACKUP=0;
PoolT_max="$Block_diff";

## Main process ##
##################
while :
do
    INIT_JSTATS;
    POOLTOOL;
    EXPLORER_CHECK;
    FLATLINERS_CHECK;
        if ([ "$RESU" -gt 0 ] && [[ "$PoolToolHeight" != "$lastBlockHeight" || "$PoolToolHeight" == "000000" ]] && [[ "$lastBlockHeight" -lt $(($PoolT_max - $Block_delay)) ]]) || [[ "$lastBlockHeight" -lt $(($PoolT_max - $Block_diff)) ]] || [[ "$FLATLINERSCOUNTER" -gt "$FLATCYCLES" ]];
        then
             echo -e "\\t\\t-->  Evaluating Recovery Restart ";
             sleep $FREQ;
             until [ $TRY -gt $RECOVERY_CYCLES ]; 
             do
                INIT_JSTATS;
                EXPLORER_CHECK;
                FLATLINERS_CHECK;
                POOLTOOL;
                PRINT_SCREEN;
                        if ([ "$RESU" -gt 0 ] && [[ "$PoolToolHeight" != "$lastBlockHeight" || "$PoolToolHeight" == "000000" ]] && [[ "$lastBlockHeight" -lt $(($PoolT_max - $Block_delay)) ]]) || [[ "$lastBlockHeight" -lt $(($PoolT_max - $Block_diff)) ]] || [[ "$FLATLINERSCOUNTER" -gt "$FLATCYCLES" ]];
                        then
                            sleep 2;
                            echo -e "Try: $RED$TRY$NC/$ORANGE$RECOVERY_CYCLES$NC before recovery restart.";

                                # YOUR Pager Fork msg
                                if [[ "$TRY" -gt "$ALERT_MINIMUM" || "$FLATLINERSCOUNTER" -gt "$ALERT_MINIMUM" ]];
                                then
                                    PAGER;
                                    echo -e "\\n \\t\\t\\t$RED-->  Warning alert sent <--$NC";
                                fi
                                # RECOVERY RESTART CONDITIONS
                                if [[ "$TRY" -eq "$RECOVERY_CYCLES" || "$FLATLINERSCOUNTER" -gt "$FLATCYCLES" ]];
                                then
                                    echo -e "\\n \\t\\t$RED--> Try:$TRY and/or FLATLINERSCOUNTER:$FLATLINERSCOUNTER !!! \\n\\t\\t--> Recovering...$NC";
                                    RECOVERY_RESTART;
                                    TRY="$RECOVERY_CYCLES";
                                    let TRY+=1;
                                    FLATLINERSCOUNTER=0;
                                    sleep 180;
                                else
                                    let TRY+=1;
                                fi
                        # Recovery waiting cycle
                            sleep $FORK_FREQ;
                        else
                            echo -e "\\t\\t-->$GREEN $DATE Restart Aborted $NC";
                            let TRY="$RECOVERY_CYCLES";
                            let TRY+=1;
                        fi
             done
                sleep 1;
        else
            sleep 1;
            INIT_JSTATS;
            POOLTOOL_S;
            POOLTOOL;
            FLATLINERS_CHECK;
            PRINT_SCREEN;
            EVAL_PAGE_BLOCK;
            STORAGE_BACKUP;
            TRY=0;
            sleep $FREQ;
        fi
        TRY=0;
        FLATLINERSCOUNTER=0;
done
