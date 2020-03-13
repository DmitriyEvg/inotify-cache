# inotify-cache
Daemon "inotify-cache" for auto-cleaning the local cache and CloudFlare cache in wordpress projects

The daemon monitors events in the specified folder (in wordpress projects it is wp-content / cache) and when changes are detected, it gently cleans the cache of various types.

