#!/bin/bash

MAX_MATCH_PER_PG=20
WORKDIR=$(pwd)
RES=$WORKDIR/res

if [ ! -d $RES ]; then
    mkdir -p $RES
fi

MATCHES=$RES/.matches.txt
find -type f -name '*.div*' > $MATCHES

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
tdivs=/tmp/.divs

while read line
do
    cat $line >> $tdivs
    ctr=$(($ctr + 1))

    if [ $ctr -eq $MAX_MATCH_PER_PG ]; then
        echo """$HTML_HEADER$(cat $tdivs)$HTML_TRAILER""" > $RES/page-$PGCOUNT.html
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
$HTML_TRAILER""" > index.html

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
""" > "$RES"/style.css

PGCOUNT=$(($PGCOUNT - 1))

echo """
var basePath = '"$RES"'
var ctr = 0
var ctrMax = '"$PGCOUNT"'

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


