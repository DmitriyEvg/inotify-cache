# inotify-cache
Daemon "inotify-cache" for auto-cleaning the local cache and CloudFlare cache in wordpress projects

The daemon monitors events in the specified folder (in wordpress projects it is wp-content / cache) and when changes are detected, it smart cleans the cache of various types.

# install

* git clone https://github.com/DmitriyEvg/inotify-cache.git
* cd inotify-cache
* cp service/inotify-cache.service /etc/systemd/system/
* systemctl daemon-reload
* systemctl enable inotify-cache.service (autostart boot)

# required settings

## Main URL
* domName="YOUR_DOMAIN_NAME"

## Notify settings
* src_dir="PATH_TO_WP_CACHE_FOLDER"
* events="delete"
* daemon_path="PATH_TO_DAEMON_FOLDER"

## Telegram API settings
* bot_token="YOUR_VALUE"
* chat_id="YOUR_VALUE"

## CloudFlare API settings
* zoneID="YOUR_VALUE"
* token="YOUR_VALUE"

# start|stop|restart daemon
* systemctl (start|stop|restart) inotify-cache.service
