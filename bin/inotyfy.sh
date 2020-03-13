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
function get_timestamp {
    echo $(date '+%Y%m%d%H%M%S')
}

## Telegram API messanger function
function send_message(){
    request=$(curl -s -X POST https://api.telegram.org/bot$bot_token/sendMessage -d chat_id=$1 -d text="$2")
}


## Add detect filesList for purge worker
function add_purge_file(){
    detect_fileList=$(grep -r --include *.html -l $1 $wprocket_dir)
    if [[ ! -z "$detect_fileList" ]]; then
        echo "$detect_fileList" >> $purge_local_path/$(get_timestamp)
    fi
}

## Add detect URL's for purge worker
function add_purge_url(){
    echo -e "\"$1\"" >> $purge_cloud_path/$(get_timestamp)
}


## Local files cache purge
function purge_files(){
    timestamp=$(date '+%Y%m%d%H%M%S')
    let "doneTime=$timestamp - 1"
    fileList=( $(ls $purge_local_path) )
    for fileName in ${fileList[@]}
    do
        if [[ "$fileName" -le "$doneTime" ]]; then
            remove_fileList=$(cat $purge_local_path/$fileName)
            while read LINE; do
                rm $LINE* -f
            done <<< "$remove_fileList"
            send_message $chat_id "Autopurge wp-rocket cache: $remove_fileList"
            rm $purge_local_path/$fileName -f
        fi
    done
}

## CloudFlare API purge by URL
function purge_cloudflare(){
    p_timestamp=$(date '+%Y%m%d%H%M%S')
    let "p_doneTime=$p_timestamp - 1"
    p_fileList=( $(ls $purge_cloud_path) )
    for p_fileName in ${p_fileList[@]}
    do
        if [[ "$p_fileName" -le "$p_doneTime" ]]; then
            purgeListRAW=$(cat $purge_cloud_path/$p_fileName | tr "\n" ",")
            purgeList=${purgeListRAW::-1}
            data="{\"files\":[$purgeList]}"
            purgeRequest=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zoneID/purge_cache" -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data "$data" > /dev/null)
            send_message $chat_id "Autopurge cloudflare cache: $purgeList"
            rm $purge_cloud_path/$p_fileName -f
        fi
    done
}

## Worker for purge processing
function worker(){
while true; do
    purge_files && purge_cloudflare
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
    add_purge_file $fileName
    purgeURL="https://$domName/$(echo $dirName$fileName | sed 's/wp-content/\nwp-content/g' | tail -n 1)"
    add_purge_url $purgeURL
  fi

  # wp-rocket
  if [[ "$dirName$fileName" == *"$wprocket_dir"*".html" ]]; then
    purgeURL="https://$domName/$(echo $dirName | sed "s/wp-rocket\/$domName\//\n/g" | tail -n 1)"
    add_purge_url $purgeURL
  fi

done
)
}


## Start application
inotify_files
