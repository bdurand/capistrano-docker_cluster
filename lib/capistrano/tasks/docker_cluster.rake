# frozen_string_literal: true

require "shellwords"

set :docker_roles, [:docker]

def as_docker_user
  user = fetch(:docker_user, nil)
  if user
    as(user) do
      with(fetch(:docker_env, {})) do
        yield
      end
    end
  else
    yield
  end
end

# All docker roles including servers that do not run a daemon
def all_docker_roles
  (Array(fetch(:docker_roles)) + Array(fetch(:docker_run_only_roles))).uniq
end

namespace :deploy do
  after :new_release_path, "docker:create_release"

  after :updating, "docker:update"

  after :published, "docker:restart"

  after :reverted, "docker:revert_image"

  task :restart => "docker:restart"

  # Required to be defined
  task :upload do
  end
end

namespace :docker do
  desc "create the docker release directory and pull the image if necessary"
  task :create_release do
    on release_roles(all_docker_roles) do
      execute :mkdir, "-p", release_path
    end

    if fetch(:docker_repository).include?("/")
      invoke "docker:pull"
    end
  end

  desc "Build and tag the docker image. This task does nothing by default, but can be implemented where needed."
  task :build do
  end

  desc "Update the configuration and command line arguments for running a docker deployment."
  task :update do
    invoke("docker:copy_configs")
    invoke("docker:upload_commands")
    invoke("docker:remove_revision")
  end

  desc "Prune the docker engine of all dangling images, containers, and networks."
  task :prune do
    on release_roles(all_docker_roles) do |host|
      as_docker_user do
        execute :docker, "system", "prune", "--force"
      end
    end
  end

  desc "Pull the tagged docker image from a remote repository into the local docker engine."
  task :pull => :authenticate do
    docker_image_url =  "#{fetch(:docker_repository)}:#{fetch(:docker_tag)}"
    on release_roles(all_docker_roles) do |host|
      within(release_path) do
        as_docker_user do
          docker_info = capture(:docker, "pull", docker_image_url)
          digest = docker_info.match(/Digest: (sha256:[0-9a-f]+)/)
          if digest
            execute :echo, "'#{fetch(:docker_repository)}@#{digest[1]}' > DOCKER_IMAGE_URL"
          end
        end
      end
    end
  end

  desc "Pull the pinned docker image from the current release and tag it."
  task :revert_image => :authenticate do
    on release_roles(all_docker_roles) do |host|
      within release_path do
        as_docker_user do
          docker_image_url = capture(:cat, "DOCKER_IMAGE_URL")
          if docker_image_url.include?("/")
            execute :docker, "pull", docker_image_url
          end
          execute :docker, "tag", docker_image_url, "#{fetch(:docker_repository)}:#{fetch(:docker_tag)}"
        end
      end
    end
  end

  desc "You must implement the docker:authenticate task if your respository requires credentials."
  task :authenticate do
  end

  desc "Remove the revision file if it contains placeholder text"
  task :remove_revision do
    on release_roles(all_docker_roles) do |host|
      within(release_path) do
        if test("[ -f #{Shellwords.escape(release_path)}/REVISION ]")
          revision = capture(:cat, "REVISION")
          if revision.include?(" ")
            execute :rm, "REVISION"
          end
        end
      end
    end
  end

  desc "Restart the docker containers (alias to docker:start)."
  task :restart do
    on release_roles(fetch(:docker_roles)) do |host|
      within "#{fetch(:deploy_to)}/current" do
        scripts = Capistrano::DockerCluster::Scripts.new(self)
        Array(scripts.fetch_for_host(host, :docker_apps)).each do |app|
          as_docker_user do
            execute "bin/start", app, "--force"
          end
        end
      end
    end
  end

  desc "Start the docker containers."
  task :start do
    on release_roles(fetch(:docker_roles)) do |host|
      within "#{fetch(:deploy_to)}/current" do
        scripts = Capistrano::DockerCluster::Scripts.new(self)
        Array(scripts.fetch_for_host(host, :docker_apps)).each do |app|
          as_docker_user do
            execute "bin/start", app
          end
        end
      end
    end
  end

  desc "Stop the docker containers."
  task :stop do
    on release_roles(fetch(:docker_roles)) do |host|
      within "#{fetch(:deploy_to)}/current" do
        scripts = Capistrano::DockerCluster::Scripts.new(self)
        Array(scripts.fetch_for_host(host, :docker_apps)).each do |app|
          as_docker_user do
            execute "bin/stop", app
          end
        end
      end
    end
  end

  desc "Upload the commands to stop and start the application docker containers."
  task :upload_commands do
    on release_roles(fetch(:docker_roles)) do |host|
      within fetch(:release_path) do
        scripts = Capistrano::DockerCluster::Scripts.new(self)
        execute(:mkdir, "-p", "bin")
        docker_cluster_path = File.join(__dir__, "..", "..", "..", "bin", "docker-cluster")
        upload! docker_cluster_path, "bin/docker-cluster"
        upload! StringIO.new(scripts.start_script(host)), "bin/start"
        upload! StringIO.new(scripts.stop_script(host)), "bin/stop"
        upload! StringIO.new(scripts.run_script(host)), "bin/run"
        execute :chmod, "a+x", "bin/*"
      end
    end
    on release_roles(fetch(:docker_run_only_roles)) do |host|
      within fetch(:release_path) do
        scripts = Capistrano::DockerCluster::Scripts.new(self)
        execute(:mkdir, "-p", "bin")
        docker_cluster_path = File.join(__dir__, "..", "..", "..", "bin", "docker-cluster")
        upload! docker_cluster_path, "bin/docker-cluster"
        upload! StringIO.new(scripts.run_script(host)), "bin/run"
        execute :chmod, "a+x", "bin/*"
      end
    end
  end

  desc "Copy configuration files used to start the docker containers."
  task :copy_configs do
    on release_roles(all_docker_roles) do |host|
      within fetch(:release_path) do
        configs = Capistrano::DockerCluster::Scripts.new(self).docker_config_map(host)
        execute(:mkdir, "-p", "config")
        configs.each do |name, local_path|
          upload! local_path, "config/#{name}"
        end
      end
    end
  end
end
