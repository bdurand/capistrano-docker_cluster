# Capistrano Docker Cluster

This gem provides a recipe to use capistrano to deploy docker applications.

This allows you to deploy an application across a cluster of servers running docker. There are, of course, other methods of doing this (kubernetes, docker-compose, etc.). This method can fill a nitch of allowing you to dockerize your application but keep the deployment simple and use existing configs if you're already deploying via capistrano.

You application will be deployed by pulling a tag from a docker repository on the remote servers and then starting it up as a cluster using the `bin/docker_cluster` script. This script will start a cluster of docker containers by spinning up a specified number of containers from the same image and configuration. It does this gracefully by first shutting down any excess containers and then restarting the containers one at a time. The script can perform an optional health check to determine if a container is fully running before shutting down the next contaner.

If you specify a port mapping for the containers, the container ports will be mapped to incrementing host ports so you can run multiple server containers fronted by a load balancer.

The full set of arguments can be found in the `bin/docker-cluster` script.

## Configuration

The deployment is configured with the following properties in your capistrano recipe.

* `docker_repository` - The URI for the repository where to pull images from. If you are building images on the docker host (i.e. for a staging server), this can just be the local respoitory.

* `docker_tag` - The tag of the image to pull for starting the containers.

* `docker_roles` - List of server roles that will run docker containers. This defaults to `:docker`, but you can change it to whatever server roles you have in your recipe.

* `docker_user` - User to use when running docker commands on the remote host. This user must have access to the docker daemon. Default to the default capistrano user.

* `docker_env` - Environment variables needed to run docker commands. You may need to set `HOME` if you are pulling docker images from a remote repository using a use that is not the default deploy user.

* `docker_apps` - List of apps to deploy. Each app is deployed to its own containers with its own configuration. This value should usually be defined on a server role.

* `docker_prefix` - Optional prefix to attach to docker container names. This can be used to distinguish containers where multiple applications are running on the same host with the same `docker_apps` names (for instance, if you run staging containers on the same hardware as your production containers).

* `docker_configs` - List of global configuration files for starting all containers.

* `docker_app_configs` - Map of configuration files for starting specific docker apps.

* `docker_configs_<app>` - List of global configuration files for starting a docker app.

* `docker_args` - List of global command line arguments for all continers.

* `docker_app_args` - Map of command line arguments for starting specific docker apps.

* `docker_args_<app>` - List of global command line arguments for starting a specific docker app.

Directory structures are ignored when configuration filse copies to servers for `docker_configs` and `docker_app_configs`. This means you can only have one file with a given base name in all you configuration files. So, `config/app/web.properties` and `config/production/web.properties` will both be copied to `confg/web.properties` on the servers. You can use this feature to overwrite whole files if you need to, but otherwise you'll need to use unique file names.

### Example Configuration

```ruby
set :docker_repository, repository.example.com/myapp

set :docker_tag, ENV.fetch("tag")

# Define two apps; the web app will run on both server01 and server02
role :web, [server01, server02], user: 'app', docker_apps: [:web]
role :async, [server01], user: 'app', docker_apps: [:async]

# These configuration files will apply to all containers
set :docker_configs, ["config/volumes.properties"]

# Unlike config files, args can be dynamically generated at runtime
set :docker_args, ["--env=ASSET_HOST=#{ENV.fetch('asset_host')}"]

# These configuration files and args will apply only to each app.
set :docker_app_configs, {
  web: ["config/web.properties"],
  async: ["config/async.properties"]
}

set :docker_app_args, {
  web: ["--env=SERVER_HOST=#{fetch(:server_host)}"]
}

# If your capistrano user doesn't have access to the docker daemon, you can specify a different user.
set :docker_user, "root"

# You can also specify environment variables that may be needed for running docker commands.
set :docker_env, {"HOME" => "/root"}
```

## Server Scripts

Scripts to control your docker applications are put into the `bin` directory in the capistrano target directory. These scripts are wrappers around the `bin/docker-cluster` script and supply the configuration values to that script for each app you've defined.

### bin/start

```bash
bin/start app [additional arguments]
```

* The start script will start up the docker containers for you app.
* If the containers are not running, they will be started.
* If excess containers are running, they will be stopped.
* If the containers are running, but they are running on a different image version, they will be replaced one at a time by new containers.


### bin/stop

```bash
bin/stop app
```

* All the containers associated with the app will be stopped.

### bin/run

```bash
bin/run app [additional arguments]
```

* Start a one off container with the specified app config.
* The normal port mapping used for the cluster will not be included; if you want to expose ports, you'll need to supply the port mapping.
* All apps defined in `docker_apps` as well as `docker_app_configs` and `docker_app_args` will be included as apps. This allows you to set up things like a "console" app which will open a console on a container for debugging, etc. without having it be part of the cluster apps.

## Capfile and SCM setting

The deployment does not require a source control management system to perform the build. To turn off this feature you need to include this in your project's Capfile to include the Docker deployment recipe and turn off the default (git) SCM setting for capistrano.

```ruby
  require 'capistrano/docker_cluster'
  install_plugin Capistrano::Scm::None::Plugin
```

## Remote Repository

If your `docker_repository` points to a remote repository, then the tag specified by `docker_tag` will be pulled from that repository during the deploy. If the repository requires authentication, then you should implement the `docker:authenticate` task to authenticate all servers in the `docker_role` role with the repository. You can use the `as_docker_user` method to run docker commands as the user specified in `docker_user`.

### Example Authentication with Amazon ECR

```ruby
namespace :docker do
  task :authenticate do
    bin_dir = "#{fetch(:release_path)}/bin"
    ecr_login_path = "#{bin_dir}/ecr_login"
    on release_roles(fetch(:docker_roles)) do |host|
      execute(:mkdir, "-p", bin_dir)
      upload! StringIO.new(ecr_login_script), ecr_login_path
      as_docker_user do
        execute :bash, ecr_login_path
      end
    end
  end
end

# Script to run the aws ecr get-login results, but with passing the password in
# via STDIN so that it doesn't appear in the capistrano logs.
def ecr_login_script
  <<~BASH
    #!/usr/bin/env bash

    set -o errexit

    read -sra cmd < <(/usr/bin/env aws ecr get-login --no-include-email)
    pass="${cmd[5]}"
    unset cmd[4] cmd[5]
    /usr/bin/env "${cmd[@]}" --password-stdin <<< "$pass"
  BASH
end
```

## Building Docker Image

If you need to build the docker image on the remote host as part of the deploy (for example if you're deploying pre-release code to a staging server), you can implement the `docker:build` task to build your docker image. You must also tag the image with the value in the `:docker_tag` property.
