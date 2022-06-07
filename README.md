# Search logs
A bash script to search cloudwatch logs of multiple accounts from the command line.

## What is it searching?
The tool will search and report findings according to a rule file that you chose. A default file is in `rules.txt` found in this repo.

## Project Status
Work in progress. The main features are implemented but lacks testing.

## Install
The scripts should only require [aws-cli](https://github.com/aws/aws-cli/) as a dependecy.

## Configure

1. Create a config file

    ```bash
    ./search-logs.sh -i
    ```

    or

    ```bash
    ./search-logs.sh -r eu-west-1 -i
    ```

2. Edit that file according to your configuration.

Here is an example:
```ini
[search logs]
; supported formats are json, csv and text (unformatted)
FORMAT=json
; if online is false, the log events will be donwloaded and searched locally
; if online is true, the logs will be searched online
; offline is slower the first time but subsquent search with different rule files or the same are faster
ONLINE=False
OUT_DIRECOTRY=.
; Full path of rules file
RULES_FILE=/home/user/tools/log-checker/rules.txt
; before downloading the logs the script will prompt if you want to continue
; with some user information so that you can verify that you are using the correct profile
; if set to false this check will be skipped
CHECK_USER=False

[aws]
REGION=us-east-1
; arrays format must be [a, b, c]
; make sure that the groups exists for the selected profile
; leave empty to search all groups
LOG_GROUPS=
; list of awscli profiles
PROFILES=[default, test]
; for offline search you can specify the maximum number of stream and events downloaded
; set to 0 to ingore them
MAX_LOG_STREAMS=100
MAX_STREAM_EVENTS=0
; dates format must be 1651237864
; Events with a time-stamp earlier than this time are not included
; if not set will be now-delta 
LOGS_START_TIME=
; Events with a timestamp equal to or later than this time are not included
; if not set will be empty so up to the most recent one
LOGS_END_TIME=
DELTA=10000
```

## Operation Modes

### 1. Online
* Will run log insight queries on aws services
* Will not download files
* There is a maximum of allowed parralel queries online set by aws
* You need to wait for the query to complete to see the results
* Each time you run the script aws needs to recompute the query search
* If the query timesout or the connection fails all the progress will be lost

### 2. Offline (Default)
* Will run grep on the downloaded events with the speficied ruleset
* Will download the logs events
* The logs are donwloaded one at a time
* Results are reported as soon as the events are downloaded
* Each time you run the script the old events files will be reused and the new one downloaded
* Progress is kept by keeping the files on the disk

## Run
```bash
./search-logs.sh -c ./search-logs.ini
```

## Offline Mode Output
The tool will create the following files and direcories inside `OUT_DIRECOTRY`. The tool output will printed on the stdout and in `local-scan.FORMAT` file, in this case `FORMAT` is json.
```tree
.
├── <profile>
│   └── <region>
│       ├── <logname>
│       │   └── <logname with slashes will retain the directory structure>
│       │       └── <logname>
│       │           ├── events
│       │           │   ├── 141d8cd98f00b204e9800998ecf8427e-events.json
│       │           │   ├── ...
│       │           │   └── d41d8cd98f00b204e9800998ecf8427e-events.json
│       │           ├── matches
│       │           │   ├── 141d8cd98f00b204e9800998ecf8427e-matches.log
│       │           │   ├── ...
│       │           │   └── d41d8cd98f00b204e9800998ecf8427e-matches.log
│       │           └── Varia-DocumentDistributor-streams.json
│       ├── local-scan.json
│       ├── local-scan.json.old.1651244677
│       ├── local-scan.log
│       └── local-scan.log.old.1651244677

```

## Online Mode Output
The tool will create the following files and direcories inside `OUT_DIRECOTRY`. The tool output will printed on the stdout and in `local-scan.FORMAT` file, in this case `FORMAT` is json.
```tree
.
├── <profile>
│   └── <region>
│       ├── queries
│       │   ├── 141d8cd98f00b204e9800998ecf8427e.json
│       │   ├── ...
│       │   └── d41d8cd98f00b204e9800998ecf8427e.json
│       ├── all-$(date +%s)-log.txt
│       ├── local-scan.json
│       ├── local-scan.json.old.1651244677
│       ├── local-scan.log
│       └── local-scan.log.old.1651244677

```

## TODO
1. Testing and bug fixing
2. Improve Output format
3. Change region to an array of regions
