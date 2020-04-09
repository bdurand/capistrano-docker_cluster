# frozen_string_literal: true

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

namespace :deploy do
  after :new_release_path, "docker:create_release"

  before :updating, "docker:set_image_id"

  after :updating, "docker:update"

  after :published, "docker:restart"

  after :reverted, "docker:pull_current"

  # Required to be defined
  task :upload do
  end
end

namespace :docker do
  desc "create the docker release directory and pull the image if necessary"
  task :create_release do
    on release_roles(fetch(:docker_roles)) do
      execute :mkdir, "-p", release_path
    end

    if fetch(:docker_repository).include?("/")
      invoke "docker:pull"
    end
  end

  desc "Set the id of the tagged docker image. This is also set as the REVISION in the deploy."
  task :set_image_id => :build do
    on release_roles(fetch(:docker_roles)).first do
      docker_tag_url =  "#{fetch(:docker_repository)}:#{fetch(:docker_tag)}"
      as_docker_user do
        image_id = capture(:docker, "image", "ls", "--no-trunc", "--format", "'{{.ID}}'", docker_tag_url)
        set :docker_image_id, image_id
      end
    end
  end

  desc "Build and tag the docker image. This task does nothing by default, but can be implemented where needed."
  task :build do
  end

  desc "Update the configuration and command line arguments for running a docker deployment."
  task :update => :set_image_id do
    invoke("docker:copy_configs")
    invoke("docker:upload_commands")
  end

  desc "Prune the docker engine of all dangling images, containers, and networks."
  task :prune do
    on release_roles(fetch(:docker_roles)) do |host|
      as_docker_user do
        execute :docker, "system", "prune", "--force"
      end
    end
  end

  desc "Pull the tagged docker image from a remote repository into the local docker engine."
  task :pull => [:authenticate, :set_image_id] do
    docker_image_url =  "#{fetch(:docker_repository)}:#{fetch(:docker_tag)}"
    on release_roles(fetch(:docker_roles)) do |host|
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

  desc "Pull the image that was used in the release."
  task :pull_current => :authenticate do
    on release_roles(fetch(:docker_roles)) do |host|
      within "#{fetch(:deploy_to)}/current" do
        as_docker_user do
          docker_image_url = capture(:cat, "DOCKER_IMAGE_URL")
          if docker_image_url.include?("/")
            execute :docker, "pull", docker_image_url
          end
        end
      end
    end
  end

  desc "You must implement the docker:authenticate task if your respository requires credentials."
  task :authenticate do
  end

  desc "Restart the docker containers (alias to docker:start)."
  task :restart do
    invoke("docker:start")
  end

  desc "Restart the docker containers."
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
        execute(:mkdir, "-p", "bin")
        scripts = Capistrano::DockerCluster::Scripts.new(self)
        docker_cluster_path = File.join(__dir__, "..", "..", "..", "bin", "docker-cluster")
        upload! docker_cluster_path, "bin/docker-cluster"
        upload! StringIO.new(scripts.start_script(host)), "bin/start"
        upload! StringIO.new(scripts.stop_script(host)), "bin/stop"
        upload! StringIO.new(scripts.run_script(host)), "bin/run"
        execute :chmod, "a+x", "bin/*"
      end
    end
  end

  desc "Copy configuration files used to start the docker containers."
  task :copy_configs do
    on release_roles(fetch(:docker_roles)) do |host|
      within fetch(:release_path) do
        execute :echo, "'#{fetch(:docker_image_id)[7, 12]}' > REVISION"

        configs = Capistrano::DockerCluster::Scripts.new(self).docker_config_map(host)
        execute(:mkdir, "-p", "config")
        configs.each do |name, local_path|
          upload! local_path, "config/#{name}"
        end
      end
    end
  end
end
