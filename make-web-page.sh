#!/bin/bash

MAX_MATCH_PER_PG=20
WORKDIR=$(pwd)

function html_escape {
    echo $1 | tr -d "\\<>'\""
}

while getopts ":m:w:" opt; do
    case $opt in
    m)
        MAX_MATCH_PER_PG=$OPTARG
        ;;
    w)
        WORKDIR="$OPTARG"
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
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

RES="$WORKDIR/res"

if [ ! -d $RES ]; then
    mkdir -p $RES
fi

MATCHES=$RES/.matches.txt
find $WORKDIR -type f -name '*.match' > $MATCHES

HTML_HEADER="""<!DOCTYPE html>
<html>
    <head>
        <meta charset='utf-8'>
        <link rel='stylesheet' type='text/css' href='"$RES"/style.css' />
    </head>
    <body>
        <div class='ctn'>
"""

HTML_TRAILER="""</div>
        <script src='"$RES"/script.js'></script>
    </body>
</html>
"""

PGCOUNT=0
ctr=0
tdivs=$(tempfile)

while read line
do
    group=$(cat $line | sed -n '1p') 
    stream=$(cat $line | sed -n '2p') 
    event_file_path=$(cat $line | sed -n '3p') 
    cloudwatch_url=$(cat $line | sed -n '4p') 
    keywords_matched=$(cat $line | sed -n '5p') 

    echo """
    <div>
        <ul>
            <li>$( html_escape $keywords_matched )</li>
            <li><a href='$( html_escape $cloudwatch_url )' target='_blank'>Open stream in CloudWatch</a></li>
            <li>$( html_escape $group )</li>
            <li>$( html_escape $stream )</li>
            <li><a href='$( html_escape $event_file_path )' target='_blank'>Open stream file</a></li>
        </ul>
    </div>
    """ >> $tdivs

    ctr=$(($ctr + 1))

    if [ $ctr -eq $MAX_MATCH_PER_PG ]; then
        echo """$HTML_HEADER<div class='mh'>$(cat $tdivs)</div>$HTML_TRAILER""" > $RES/page-$PGCOUNT.html
        ctr=0
        PGCOUNT=$(($PGCOUNT + 1))
        rm $tdivs
    fi
done < $MATCHES 

echo """$HTML_HEADER
            <iframe id='pgctn' style='height: 90vh;' src='"$RES/page-0.html"'></iframe>
            <div class='bth'>
                <button onclick='changeDir(-1)' >&lt;</button>
                <button onclick='changeDir(1)' >&gt;</button>
            </div>
$HTML_TRAILER""" > $WORKDIR/index.html

echo """
.ctn {
    display: flex;
    flex-flow: column;
    height: 100vh;
}
.bth {
    display: flex;
    flex-flow: row;
    justify-content: space-evenly;
}
.mh {
    display: flex;
    flex-wrap: wrap;
}
""" > "$RES"/style.css

PGCOUNT=$(($PGCOUNT - 1))

echo """
var basePath = '"$RES"'
var ctr = 0
var ctrMax = "$PGCOUNT"

function changeDir(i) {
    ctr += i
    if (ctr < 0) {
        ctr = 0
    }
    if (ctr > ctrMax) {
        ctr = ctrMax
    }
    document.getElementById('pgctn').src=basePath+'/page-'+ctr+'.html'
}
""" > "$RES/"script.js


