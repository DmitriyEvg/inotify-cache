#!/bin/bash

# Main URL
domName="YOUR_DOMAIN_NAME"

# Notify settings
src_dir="PATH_TO_WP_CACHE_FOLDER"
autoptimize_dir="${src_dir}autoptimize/"
wprocket_dir="${src_dir}wp-rocket/"
events="delete"
daemon_path="PATH_TO_DAEMON_FOLDER"
tasks_path="$daemon_path/tasks"
checkCache_path="$tasks_path/checkCache"
purgeCache_path="$tasks_path/purgeCache"
trash_path="$tasks_path/trash"

# Telegram API settings
bot_token="YOUR_VALUE"
chat_id="YOUR_VALUE"

# CloudFlare API settings
token="YOUR_VALUE"
api_url="WORKER_URL"
api_everything="WORKER_URL"

## Get timestamp function
function get_timestamp() {
    echo $(date '+%Y%m%d%H%M')
}

## Telegram API messanger function
function send_message(){
    request=$(curl -s -X POST https://api.telegram.org/bot$bot_token/sendMessage -d chat_id=$1 -d text="$2")
}


## Add task for purge worker
function add_cacheCheck_task(){
        echo "task up" >> "$checkCache_path/task"
}

# Get autoptimize_fileList
function get_autoptimize_fileList(){
    # autoptimize_fileList
    css_fileList=$(ls ${autoptimize_dir}css | grep -E 'autoptimize_[a-zA-Z0-9]{32}.css')
    js_fileList=$(ls ${autoptimize_dir}js | grep -E '^autoptimize_[a-zA-Z0-9]{32}.js')
    autoptimize_fileList=$(echo -e "${css_fileList}\n${js_fileList}")
    echo "$autoptimize_fileList"
}

## checkCache valid links
function checkCache(){

    if [ -f "$checkCache_path/task" ]; then

        send_message $chat_id "run checkCache process"

        # html_fileList
        html_fileList=$(find $wprocket_dir -name *.html)

        while read cacheFile; do
            autoptimize_fileList=$(get_autoptimize_fileList)
            page_autoptimizeLinks="$(cat $cacheFile | grep -o -E 'autoptimize_[a-zA-Z0-9]{32}.(css|js)' | uniq)"
            page_autoptimizeLinksCount=$(echo "$page_autoptimizeLinks" | wc -l)
            reg_autoptimizeLinks=$(echo $page_autoptimizeLinks | tr " " "|")

            validLinksCount=$(echo "$autoptimize_fileList" | grep -E "$reg_autoptimizeLinks" | wc -l)

            if [ "$page_autoptimizeLinksCount" -ne "$validLinksCount" ]; then

                # Remove current cache files
                mv "${cacheFile}" "$trash_path/" -f
                rm "${cacheFile}_gzip" -f

                # Send preload request
                cacheURL="https://$(echo "$cacheFile" | sed "s/wp-rocket\//\n/g" | tail -n 1 | sed 's/index-https.html//g')"
                curl -s -k -o /dev/null "$cacheURL"
            fi
        done <<< "$html_fileList"

        send_message $chat_id "checkCache process complete"

        rm "$checkCache_path/task" -f

    fi
}


## Add task for purge CloudFlare
function add_purgeCache_task(){
        echo "\"$1\"," >> "$purgeCache_path/$(get_timestamp)"
}

## task purge CloudFlare
function purgeCache(){
    taskFilesList=( $(ls $purgeCache_path) )
    let "doneFileList=$(get_timestamp) - 1"

    for taskFile in ${taskFilesList[@]}; do
        if [ "$taskFile" -le "$doneFileList" ]; then
            countURL=$(cat "$purgeCache_path/$taskFile" | uniq | wc -l )
            if [ "$countURL" -gt "10" ]; then
                rm "$purgeCache_path/$taskFile"
                purge_cloudflareEverything
            else
                doneList=$(cat "$purgeCache_path/$taskFile" | uniq | tr -d "\n")
                rm "$purgeCache_path/$taskFile"
                purge_cloudflareURL "${doneList::-1}"
            fi
        fi
    done
}


## CloudFlare API purge by URL
function purge_cloudflareURL(){
    data="{\"files\":[$1]}"
    send_message $chat_id "start purge CF by URL's"
    purgeRequest=$(curl --resolve "$domName:443:104.25.117.7" -s -X POST "$api_url" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type:application/json" --data "$data")
    send_message $chat_id "purge CF by URL's done"
}

## CloudFlare API purge by Everithing
function purge_cloudflareEverything(){
    send_message $chat_id "start purge CF everything"
    purgeRequest=$(curl --resolve "$domName:443:104.25.117.7" -s -X POST "$api_everything" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type:application/json" \
        --data '{"purge_everything":true}')
    send_message $chat_id "purge CF everything done"
}

## Worker for purge processing
function worker(){
while true; do
    checkCache && purgeCache
    sleep 5
done
}


## Main function inotify files
function inotify_files(){
#start worker
worker &
IFS='
'
inotifywait --event $events --recursive --format '%e %w %f' --monitor $src_dir |\
(
while read
do
  # Events handling

  # Get $REPLY params
  eventName=$(echo $REPLY | cut -f 1 -d' ')
  dirName=$(echo $REPLY | cut -f 2 -d' ')
  fileName=$(echo $REPLY | cut -f 3 -d' ')

  # detect "DELETE" in autoptimize cache
  if [[ "$dirName" == *"$autoptimize_dir"* ]]; then
    if [ ! -f "$purge_local_path/task" ]; then
        add_cacheCheck_task
    fi
  fi

  # detect "DELETE" in wp-rocket cache
  if [[ "$dirName$fileName" == *"$wprocket_dir"*".html" ]]; then
    cacheURL="https://$(echo "$dirName$fileName" | sed "s/wp-rocket\//\n/g" | tail -n 1 | sed 's/index-https.html//g')"
    #echo -e "$eventName\t$cacheURL"
    add_purgeCache_task "$cacheURL"
  fi

done
)
}

## Start application
inotify_files
