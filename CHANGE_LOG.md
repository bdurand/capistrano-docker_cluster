# 1.0.7

* Fix rollback order so pull and tag is done on release path to get the correct version.

# 1.0.6

* Store docker image url in release directory.
* Add support to pull the docker image on rollback.
* Use docker tags in scripts instead of image ids.

# 1.0.5

* Add "--no-" prefix on arguments to remove them.
* Add ability to turn off healthcheck entirely.

# 1.0.4

* Add --clear-command argument to clear the docker command buffer.

# 1.0.3

* Fix use of `--` to send command arguments.

# 1.0.2

* Allow specifying app specific settings as capistrano variables `docker_app_configs_<app>` and `docker_app_args_<app>`.

# 1.0.1

* Fix module naming convention to match gem name.

# 1.0.0

* Initial release
