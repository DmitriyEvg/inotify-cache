#!/bin/bash

# Main URL
domName="YOUR_DOMAIN_NAME"

# Notify settings
src_dir="PATH_TO_WP_CACHE_FOLDER"
autoptimize_dir="${src_dir}autoptimize/"
wprocket_dir="${src_dir}wp-rocket/"
events="delete"
daemon_path="PATH_TO_DAEMON_FOLDER"
purge_path="$daemon_path/purgelist"
purge_local_path="$purge_path/localcache"
purge_cloud_path="$purge_path/cloudflare"

# Telegram API settings
bot_token="YOUR_VALUE"
chat_id="YOUR_VALUE"

# CloudFlare API settings
zoneID="YOUR_VALUE"
token="YOUR_VALUE"
api_url="https://api.cloudflare.com/client/v4/zones/$zoneID/purge_cache"

## Get timestamp function
function get_timestamp() {
    echo $(date '+%Y%m%d%H%M%S')
}

## Telegram API messanger function
function send_message(){
    request=$(curl -s -X POST https://api.telegram.org/bot$bot_token/sendMessage -d chat_id=$1 -d text="$2")
}


## Add task for purge worker
function add_filePurge_task(){
        echo "task up" >> "$purge_local_path/task"
}

# Get autoptimize_fileList
function get_autoptimize_fileList(){
    # autoptimize_fileList
    css_fileList=$(ls ${autoptimize_dir}css | grep -E 'autoptimize_[a-zA-Z0-9]{32}.css')
    js_fileList=$(ls ${autoptimize_dir}js | grep -E '^autoptimize_[a-zA-Z0-9]{32}.js')
    autoptimize_fileList=$(echo -e "${css_fileList}\n${js_fileList}")
    echo "$autoptimize_fileList"
}

## Local files cache purge
function purge_files(){
    taskDetect=$(ls $purge_local_path | wc -l)

    if [ "$taskDetect" -ne "0" ]; then

        rm "$purge_local_path/task" -f

        send_message $chat_id "run purge cache process"

        # html_fileList
        html_fileList=$(find $wprocket_dir -name *.html)

        while read cacheFile; do
            autoptimize_fileList=$(get_autoptimize_fileList)
            page_autoptimizeLinks="$(cat $cacheFile | grep -o -E 'autoptimize_[a-zA-Z0-9]{32}.(css|js)' | uniq)"
            page_autoptimizeLinksCount=$(echo "$page_autoptimizeLinks" | wc -l)
            reg_autoptimizeLinks=$(echo $page_autoptimizeLinks | tr " " "|")

            validLinksCount=$(echo "$autoptimize_fileList" | grep -E "$reg_autoptimizeLinks" | wc -l)

            if [ "$page_autoptimizeLinksCount" -ne "$validLinksCount" ]; then
                rm "${cacheFile}" -f
                rm "${cacheFile}_gzip" -f
                cacheURL="https://$(echo "$cacheFile" | sed "s/wp-rocket\//\n/g" | tail -n 1 | sed 's/index-https.html//g')"
                curl -s -k -o /dev/null "$cacheURL"
                purge_cloudflare "$cacheURL"
            fi
        done <<< "$html_fileList"

        send_message $chat_id "purge cache process complete"
    fi
}

## CloudFlare API purge by URL
function purge_cloudflare(){
    data="{\"files\":[\"$1\",{\"url\":\"$1\"}]}"
    purgeRequest=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zoneID/purge_cache" -H \
        "Authorization: Bearer $token" -H "Content-Type: application/json" --data "$data")
}

## Worker for purge processing
function worker(){
while true; do
    purge_files
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

  # autoptimize
  if [[ "$dirName" == *"$autoptimize_dir"* ]]; then
    add_filePurge_task
  fi

  # wp-rocket
  #if [[ "$dirName$fileName" == *"$wprocket_dir"*".html" ]]; then
  #    TODO
  #fi

done
)
}

## Start application
inotify_files
