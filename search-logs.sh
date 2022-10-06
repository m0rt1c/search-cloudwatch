#!/bin/bash

CONF=""
CHECK_USER=true
DEBUG=false
EXPORT_URL=""
FORMAT="json"
LOG_GROUPS=()
LOG_GROUPS_REGEX=""
ONLINE=false
OUT_DIRECOTRY=$(pwd)
PROFILES=()
REGION="us-east-1"
RULES_FILE="rules.txt"

DELTA=100000
LOGS_END_TIME=""
LOGS_START_TIME=""
MAX_LOG_STREAMS=100
MAX_STREAM_EVENTS=0

ACCOUNT_OUT_ID="Account"
EVENTS_OUT_ID="Matching Events Path"
GROUP_OUT_ID="Group"
STREAM_OUT_ID="Stream"
REGION_OUT_ID="Region"
URL_OUT_ID="Cloud Watch Log Stream URL"
VALUES_OUT_ID="Matching Values"

function print_help {
    echo "usage: search-logs.sh [OPTIONS <profile 1> <profile 2> ... ]"
    echo "configuration file or at least one profile is required"
    echo "optional arguments:"
    echo -e "\t-c\tconfig file path"
    echo -e "\t-d\tchange output direcotory, default is current direcotry"
    echo -e "\t-f\toutput format default is text, can be text, json, csv"
    echo -e "\t-g\trules file to be used with grep -f"
    echo -e "\t-h\tshow this help message and exit"
    echo -e "\t-i\tcreates init file sample in local directory and exit"
    echo -e "\t-o\tsearch online instead of downloading the logs locally"
    echo -e "\t-r\tchange region, default is us-east-1"
    echo -e "\t-y\tskips user check"
    echo -e "\t-x\texport tar gz to endpoint"
}

function encode-stream {
    echo -n $1 | sed 's/\$/$2524/g;s/\//$252F/g;s/\[/$255B/g;s/\]/$255D/g'
}

function encode-group {
    echo $1 | sed 's/\//$252F/g;s/\[/$255B/g;s/\]/$255D/g'
}

function encode-csv {
    echo -n $@ | sed 's/,/ /g' | tr '\n' ' '
}

function remove-spaces {
    echo -n $@ | sed 's/ //g'
}

function encode-json {
    if [ $# -eq 1 ]; then
        echo -n $1 | sed 's/"/\\"/g'
    else
        comma=""
        echo -n "["
        for elem in $@; do
            echo -ne "$comma\"$(encode-json $elem)\""
            if [ "$comma" == "" ]; then
                comma=","
            fi
        done
        echo -n "]"
    fi
}

function parse-ini-string {
    grep -E "$1 ?=" $CONF | sed 's/ ?= ?/=/g' | cut -d "=" -f2 | tr -d '\n'
}

function parse-ini-bool {
    v=$(grep $1 $CONF | cut -d "=" -f2 | tr -d '\n ')
    if [ "$v" == "true" ] || [ "$v" == "True" ] || [ "$v" == "y" ] || [ "$v" == "Y" ] || [ "$v" == "Yes" ] || [ "$v" == "yes" ]; then
        echo true
    else
        echo false
    fi
}

function parse-ini-array {
    parse-ini-string $1 | tr -d '[,]'
}

function format_cloudwatch_url {
    echo -n "https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/$(encode-group $1)/log-events/$(encode-stream $2)"
}

function grep_values {
    grep -f $RULES_FILE -Eo $1 | sort -u
}

function write_text_out {
    search_out_file=$1
    echo "=============================================" | tee -a $search_out_file
    echo -e "$ACCOUNT_OUT_ID:\n$2" | tee -a $search_out_file
    echo -e "$REGION_OUT_ID:\n$REGION" | tee -a $search_out_file
    echo -e "$GROUP_OUT_ID:\n$5" | tee -a $search_out_file
    echo -e "$STREAM_OUT_ID:\n$6" | tee -a $search_out_file
    echo -e "$EVENTS_OUT_ID:\n$3" | tee -a $search_out_file
    echo "$VALUES_OUT_ID:" | tee -a $search_out_file
    grep_values $4 | tee -a $search_out_file
    echo -e "$URL_OUT_ID: \n$(format_cloudwatch_url $5 $6)" | tee -a $search_out_file
}

function store_match {
    match_file=$1.match
    events_file=$2
    group=$3
    stream=$4

    match="$group\n$stream\n$events_file\n$(format_cloudwatch_url $group $stream)\n$(grep_values $events_file)"
    echo -e $match > $match_file
}

# the first time we omit the comma before the element
# after that it will be initialized at ,
JSON_COMMA=""
function write_json_out {
    search_out_file=$1
    echo -e "$JSON_COMMA\t{" | tee -a $search_out_file
    echo -e "\t\t\"$ACCOUNT_OUT_ID\": \"$(encode-json $2)\"," | tee -a $search_out_file
    echo -e "\t\t\"$REGION_OUT_ID\": \"$(encode-json $REGION)\"," | tee -a $search_out_file
    echo -e "\t\t\"$GROUP_OUT_ID\": \"$(encode-json $5)\"," | tee -a $search_out_file
    echo -e "\t\t\"$STREAM_OUT_ID\": \"$(encode-json $6)\"," | tee -a $search_out_file
    echo -e "\t\t\"$(remove-spaces $EVENTS_OUT_ID)\": \"$(encode-json $4)\"," | tee -a $search_out_file
    values="$(encode-json $(grep_values $4))"
    # values must always be an array
    if [ ${values::1} != "[" ]; then
        values="[\"$values\"]"
    fi
    echo -e "\t\t\"$(remove-spaces $VALUES_OUT_ID)\": $values," | tee -a $search_out_file
    echo -e "\t\t\"$(remove-spaces $URL_OUT_ID)\": \"$(encode-json $(format_cloudwatch_url $5 $6))\"" | tee -a $search_out_file
    echo -en "\t}" | tee -a $search_out_file
    if [ "$JSON_COMMA" == "" ]; then
        JSON_COMMA=",\n"
    fi
}

function write_csv_out {
    search_out_file=$1
    echo "$(encode-csv $2), $(encode-csv $REGION), $(encode-csv $5), $(encode-csv $6),$(encode-csv $3), $(encode-csv $(grep_values $4)), $(encode-csv $(format_cloudwatch_url $5 $6))" | tee -a $search_out_file
}

function write_out {
    case $FORMAT in
    text)
        write_text_out "$@"
        ;;
    csv)
        write_csv_out "$@"
        ;;
    json)
        write_json_out "$@"
        ;;
    \?)
        write_text_out "$@"
        ;;
    esac
}

function write_out_header {
    search_out_file=$1
    case $FORMAT in
    csv)
        echo "$ACCOUNT_OUT_ID, $REGION_OUT_ID, $GROUP_OUT_ID, $STREAM_OUT_ID, $EVENTS_OUT_ID, $VALUES_OUT_ID, $URL_OUT_ID" | tee -a $search_out_file
        ;;
    json)
        echo -e '{\n\t"version":0.1,\n\t"results":[' | tee -a $search_out_file
        ;;
    \?)
        write_text_out "$@"
        ;;
    esac
}

function write_out_trailer {
    search_out_file=$1
    case $FORMAT in
    text)
        echo "=============================================" | tee -a $search_out_file
        ;;
    json)
        echo -e "\n\t]\n}" | tee -a $search_out_file
        ;;
    \?)
        write_text_out "$@"
        ;;
    esac
}

function copy_old_file_if_exists {
    if [ -f $1 ]; then
        # date is used to create a unique name
        # it will not reflect the old file creation time
        mv $1 $1.old.$(date +%s)
    fi
}

function start_time_option {
    if [ "$LOGS_START_TIME" != "" ]; then
        echo -n "--start-time $LOGS_START_TIME"
    else
        echo -n "--start-time $(($(date +%s%3N) - $DELTA))"
    fi
}

function end_time_option {
    if [ "$LOGS_END_TIME" != "" ]; then
        echo -n "--end-time $LOGS_END_TIME"
    else
        echo -n ""
    fi
}

function create_and_run_query {
    query_string="parse @message \"[*] *\" as loggingType, loggingMessage | filter loggingMessage like /$1/ | display loggingMessage"
    shift
    aws logs start-query --log-group-names $@ --query-string $query_string --start-time $(start_time_option) --end-time $(end_time_option) --profile $PROFILE --region $REGION | jq -r ".queryId"
}

function remote-search {
    out_dir=$1
    profile=$2
    search_log_file=$out_dir/local-scan.log
    search_out_file=$out_dir/local-scan.$FORMAT

    copy_old_file_if_exists $search_log_file
    copy_old_file_if_exists $search_out_file

    workdir=$out_dir/all-$(date +%s)
    mkdir -p $workdir/queries
    logfile=$workdir/all-$(date +%s)-log.txt
    queryids=$workdir/queries/.queryids.txt
    wait_timeout=5

    # the first time writing a json we omit the comma before the element
    # after that it will be initialized at , by write JSON
    JSON_COMMA=""

    write_out_header $search_out_file
    # at most 20 logs can be searched online at a time
    g=20
    for ((i = 0; i < ${#LOG_GROUPS[@]}; i += g)); do
        groups=("${LOG_GROUPS[@]:i:g}")

        while read rule; do
            queryid=$(create_and_run_query $rule $groups)
            t=$wait_timeout
            while [ "$queryid" = "" ]; do
                echo "Retrying query creation"
                sleep $t
                t=$((t + $wait_timeout))
                queryid=$(create_and_run_query $rule $groups)
            done
            t=$wait_timeout
            while true; do
                matches_file="$workdir/queries/$queryid.json"
                aws logs get-query-results --query-id "$queryid" --profile $PROFILE --region $REGION >$matches_file
                status=$(cat $matches_file | grep -o -e Complete -e Timeout)
                if [ "$status" = "Complete" ]; then
                    break
                fi
                if [ "$status" = "Timeout" ]; then
                    echo "Query timeout"
                    exit 1
                fi
                echo "Waiting for query completion"
                sleep $t
                t=$((t + $wait_timeout))
            done
            results=$(cat $matches_file | jq -r '.results')
            if [ "$results" != "[]" ]; then
                write_out $search_out_file $profile $matches_file $matches_file $groups "unknown stream"
                echo "Results found: $queryid\n $results"
            else
                rm "$matches_file"
            fi
        done <$RULES_FILE
    done
    write_out_trailer $search_out_file
}

function local-search {
    out_dir=$1
    profile=$2
    search_log_file=$out_dir/local-scan.log
    search_out_file=$out_dir/local-scan.$FORMAT

    copy_old_file_if_exists $search_log_file
    copy_old_file_if_exists $search_out_file

    prefix="/"
    # the first time writing a json we omit the comma before the element
    # after that it will be initialized at , by write JSON
    JSON_COMMA=""

    write_out_header $search_out_file
    for group in ${LOG_GROUPS[@]}; do
        if [ "$LOG_GROUPS_REGEX" != "" ]; then
            if [[ ! $group =~ $LOG_GROUPS_REGEX ]]; then
                continue
            fi
        fi
        echo "Reading log: $group" >>$search_log_file
        workdir=$out_dir/${group#"$prefix"}
        mkdir -p $workdir
        mkdir -p $workdir/events
        mkdir -p $workdir/matches
        streams_file=$workdir/$(basename $group)-streams.json
        if [ -f $streams_file ]; then
            echo "Streams file already exists for this group, reusing it. If you want to pull newer streams remove the file" >>$search_log_file
        else
            max_items=""
            if [ "$MAX_LOG_STREAMS" -ne 0 ]; then
                max_items="--max-items $MAX_LOG_STREAMS"
            fi
            # echo aws logs describe-log-streams --log-group-name "$group" --order-by LastEventTime --descending $max_items --profile $profile --region $REGION
            aws logs describe-log-streams --log-group-name "$group" --order-by LastEventTime --descending $max_items --profile $profile --region $REGION >$streams_file
        fi
        streamsid=$workdir/.stream-ids
        cat $streams_file | jq -r '.logStreams[].logStreamName' >$streamsid
        while read stream; do
            echo "Reading stream: $stream" >>$search_log_file
            events_file=$workdir/events/$(basename $stream)-events.json
            if [ -f $events_file ]; then
                echo "Events file already exists for this stream, reusing it. If you want to pull newer events remove the file" >>$search_log_file
            else
                limit=""
                if [ "$MAX_STREAM_EVENTS" -ne 0 ]; then
                    limit="--limit $MAX_STREAM_EVENTS"
                fi

                aws logs get-log-events --log-group-name "$group" --log-stream-name $stream $limit $(start_time_option) $(end_time_option) --start-from-head --profile $profile --region $REGION >$events_file
            fi
            matches_file=$workdir/matches/$(basename $stream)-matches.log
            grep -f $RULES_FILE -E $events_file > $matches_file
            if [ -s $matches_file ]; then
                write_out $search_out_file $profile $matches_file $events_file $group $stream
                store_match $matches_file $events_file $group $stream
            else
                rm $matches_file
            fi
        done <$streamsid
        rm $streamsid
    done
    write_out_trailer $search_out_file
}

if [ "$#" -lt 1 ] || ([ "$#" -eq 1 ] && [ "$1" == "--help" ]); then
    print_help
    exit 0
fi

while getopts ":c:d:f:g:hior:vyx:" opt; do
    case $opt in
    c)
        CONF="$OPTARG"
        if [ "$CONF" != "" ]; then
            CHECK_USER=$(parse-ini-bool "CHECK_USER")
            DEBUG=$(parse-ini-bool "DEBUG")
            FORMAT=$(parse-ini-string "FORMAT")
            LOG_GROUPS=($(parse-ini-array "LOG_GROUPS"))
            LOG_GROUPS_REGEX=$(parse-ini-string "LOG_GROUPS_REGEX")
            ONLINE=$(parse-ini-bool "ONLINE")
            OUT_DIRECOTRY=$(parse-ini-string "OUT_DIRECOTRY")
            PROFILES=($(parse-ini-array "PROFILES"))
            REGION=$(parse-ini-string "REGION")
            RULES_FILE=$(parse-ini-string "RULES_FILE")

            DELTA=$(parse-ini-string "DELTA")
            LOGS_END_TIME=$(parse-ini-string "LOGS_END_TIME")
            LOGS_START_TIME=$(parse-ini-string "LOGS_START_TIME")
            MAX_LOG_STREAMS=$(parse-ini-string "MAX_LOG_STREAMS")
            MAX_STREAM_EVENTS=$(parse-ini-string "MAX_STREAM_EVENTS")
        fi
        ;;
    d)
        OUT_DIRECOTRY="$OPTARG"
        ;;
    f)
        FORMAT="$OPTARG"
        ;;
    g)
        RULES_FILE="$OPTARG"
        ;;
    h)
        print_help
        exit 0
        ;;
    i)
        file=search-logs.ini
        if [ -s $file ]; then
            echo "$file already existst creating in a random file"
            file=search-logs-$RANDOM.ini
        fi
        echo "[search logs]
; supported formats are json, csv and text (unformatted)
FORMAT=$FORMAT
; if online is false, the log events will be donwloaded and searched locally
; if online is true, the logs will be searched online
; offline is slower the first time but subsquent search with different rule files or the same are faster
ONLINE=$ONLINE
OUT_DIRECOTRY=$OUT_DIRECOTRY
; Full path of rules file
RULES_FILE=$RULES_FILE
; before downloading the logs the script will prompt if you want to continue
; with some user information so that you can verify that you are using the correct profile
; if set to false this check will be skipped
CHECK_USER=False
; will set 'set -x'
DEBUG=False

[aws]
REGION=$REGION
; arrays format must be [a, b, c]
; make sure that the groups exists for the selected profile
; leave empty to search all groups
LOG_GROUPS=$LOG_GROUPS
; regex to filter log group names leave empty to match all log groups
LOG_GROUPS_REGEX=$LOG_GROUPS_REGEX
; list of awscli profiles
PROFILES=[$PROFILES]
; for offline search you can specify the maximum number of stream and events downloaded
; set to 0 to ingore them
MAX_LOG_STREAMS=$MAX_LOG_STREAMS
MAX_STREAM_EVENTS=$MAX_STREAM_EVENTS
; dates format must be in milliseconds like 1651247860983, for example with $(date +%s%3N)
; Events with a time-stamp earlier than this time are not included
; if not set will be now-delta 
LOGS_START_TIME=$LOGS_END_TIME
; Events with a timestamp equal to or later than this time are not included
; if not set will be empty so up to the most recent one
LOGS_END_TIME=$LOGS_START_TIME
; delta to be subtracted from now if logs start time is not set, default is two weeks
DELTA=$DELTA" >$file
        echo "created file $file"
        exit 0
        ;;
    o)
        ONLINE=true
        ;;
    r)
        REGION="$OPTARG"
        ;;
    v)
        DEBUG=true
        ;;
    y)
        CHECK_USER=false
        ;;
    x)
        EXPORT_URL="$OPTARG"
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        print_help
        exit 1
        ;;
    esac

    case $OPTARG in
    -*)
        echo "Option $opt needs a valid argument"
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

if $DEBUG; then
    set -x
fi

if [ "$FORMAT" != "text" ] && [ "$FORMAT" != "json" ] && [ "$FORMAT" != "csv" ]; then
    echo "invalid format $FORMAT"
    print_help
    exit 1
fi

if [ ${#PROFILES[@]} -eq 0 ]; then
    PROFILES="$@"
fi

export PYTHONWARNINGS="ignore:Unverified HTTPS request"

for profile in ${PROFILES[@]}; do

    if $CHECK_USER; then
        echo "Checking user..."
        aws sts get-caller-identity --profile "$profile"

        echo "proceed? [y/n]"
        read answer
        if [ $answer != "y" ]; then
            exit 0
        fi
    fi

    c=0
    for i in ${LOG_GROUPS[@]}; do
        c=$((c + 1))
    done

    if [ $c -eq 0 ]; then
        LOG_GROUPS=$(aws logs describe-log-groups --profile $profile --region $REGION | jq -r '.logGroups[].logGroupName' | tr '\n' ' ')
    fi

    profile_work_dir=$OUT_DIRECOTRY/$profile/$REGION
    mkdir -p $profile_work_dir

    if $ONLINE; then
        remote-search $profile_work_dir $profile
    else
        local-search $profile_work_dir $profile
    fi
done

if [ "$EXPORT_URL" != "" ]; then
    current_dir_name=$(basename $(pwd))
    cd ..
    tar czf $current_dir_name.tar.gz current_dir_name
    curl -F "archive=@$current_dir_name.tar.gz" $EXPORT_URL
    cd $current_dir_name
fi
