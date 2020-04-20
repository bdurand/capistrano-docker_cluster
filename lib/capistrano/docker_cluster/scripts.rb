# frozen_string_literal: true

require "time"

module Capistrano
  module DockerCluster
    class Scripts
      def initialize(context)
        @context = context
      end

      # Build a custom command line start script with the configuration arguments for
      # each docker application on the host. This allows each app to be started with
      # the predefined configuration by calling `bin/start app`.
      def start_script(host)
        apps = Array(fetch_for_host(host, :docker_apps))
        cmd = "bin/docker-cluster"
        image_id = "#{fetch(:docker_repository)}:#{fetch(:docker_tag)}"
        prefix = fetch(:docker_prefix)

        cases = []
        all = []
        apps.each do |app|
          args = app_host_args(app, host)
          start_cmd = "#{cmd} #{args.join(' ')} --name '#{prefix}#{app}' --image '#{image_id}' \"$@\""
          cases << "  '#{app}')\n    exec #{start_cmd}\n    ;;"
          all << "    #{start_cmd}"
        end

        <<~BASH
          #!/usr/bin/env bash

          # Generated: #{Time.now.utc.iso8601}
          # Docker image tag: #{fetch(:docker_repository)}:#{fetch(:docker_tag)}

          set -o errexit

          cd $(dirname $0)/..

          typeset app=$1
          if [ "$app" == "" ]; then
            >&2 echo "Usage: $0 #{apps.join('|')}|--all"
            exit 1
          fi
          shift

          case $app in
          #{cases.join("\n")}
            '--all')
          #{all.join("\n")}
              ;;
            *)
              >&2 echo "Usage: $0 #{apps.join('|')}|--all"
              exit 1
          esac
        BASH
      end

      # Build a custom command line run script with the configuration arguments for
      # each docker application on the host to run one off containers.
      def run_script(host)
        # For the run script, all configured apps are included, not just the deployed ones.
        # This allows configuring, for example, a "console" app to open up a console in a container.
        apps = Array(fetch_for_host(host, :docker_apps))
        app_configs = fetch_for_host(host, :docker_app_configs)
        apps.concat(app_configs.keys) if app_configs.is_a?(Hash)
        app_args = fetch_for_host(host, :docker_app_args)
        apps.concat(app_args.keys) if app_args.is_a?(Hash)
        apps = apps.collect(&:to_s).uniq

        cmd = "exec bin/docker-cluster"
        image_id = "#{fetch(:docker_repository)}:#{fetch(:docker_tag)}"

        cases = []
        apps.each do |app|
          args = app_host_args(app, host)
          cases << "  '#{app}')\n    #{cmd} #{args.join(' ')} --image '#{image_id}' --one-off \"$@\"\n    ;;"
        end

        <<~BASH
          #!/usr/bin/env bash

          # Generated: #{Time.now.utc.iso8601}
          # Docker image tag: #{fetch(:docker_repository)}:#{fetch(:docker_tag)}

          set -o errexit

          cd $(dirname $0)/..

          typeset app=$1
          if [ "$app" == "" ]; then
            >&2 echo "Usage: $0 #{apps.join('|')}"
            exit 1
          fi
          shift

          case $app in
          #{cases.join("\n")}
            *)
              >&2 echo "Usage: $0 #{apps.join('|')}"
              exit 1
          esac
        BASH
      end

      # Build a custom command line stop script for each docker application on the host.
      def stop_script(host)
        apps = Array(fetch_for_host(host, :docker_apps))
        prefix = fetch(:docker_prefix)

        cases = []
        all = []
        apps.each do |app|
          stop_cmd = "bin/docker-cluster --name '#{prefix}#{app}' --count 0"
          cases << "  '#{app}')\n    exec #{stop_cmd}\n    ;;"
          all << "    #{stop_cmd}"
        end

        <<~BASH
          #!/usr/bin/env bash

          # Generated: #{Time.now.utc.iso8601}
          # Docker image tag: #{fetch(:docker_repository)}:#{fetch(:docker_tag)}

          set -o errexit

          cd $(dirname $0)/..

          typeset app=$1
          if [ "$app" == "" ]; then
            >&2 echo "Usage: $0 #{apps.join('|')}|--all"
            exit 1
          fi

          case $app in
          #{cases.join("\n")}
            '--all')
          #{all.join("\n")}
              ;;
            *)
              >&2 echo "Usage: $0 #{apps.join('|')}|--all"
              exit 1
          esac
        BASH
      end

      # Returns a list of all local configuration file paths that need to be uploaded to
      # the host.
      def docker_config_map(host)
        configs = {}
        Array(fetch(:docker_configs)).each do |path|
          configs[File.basename(path)] = path
        end

        apps = Array(fetch_for_host(host, :docker_apps))
        app_configs = app_configuration(fetch(:docker_app_configs, nil))
        host_app_configs = app_configuration(host.properties.send(:docker_app_configs))
        apps += app_configs.keys if app_configs
        apps += host_app_configs.keys if host_app_configs
        apps = apps.collect(&:to_s).uniq

        if app_configs
          app_configs.values.each do |paths|
            Array(paths).each do |path|
              configs[File.basename(path)] = path
            end
          end
        end

        apps.each do |app|
          Array(fetch(:"docker_app_configs_#{app}")).each do |path|
            configs[File.basename(path)] = path
          end
        end

        Array(host.properties.docker_configs).each do |path|
          configs[File.basename(path)] = path
        end

        if host_app_configs
          host_app_configs.values.each do |paths|
            Array(paths).each do |path|
              configs[File.basename(path)] = path
            end
          end
        end

        apps.each do |app|
          Array(host.properties.send(:"docker_app_configs_#{app}")).each do |path|
            configs[File.basename(path)] = path
          end
        end

        configs
      end

      # Fetch a host specific property. If a the value is not defined as host specific,
      # then fallback to the globally defined property.
      def fetch_for_host(host, property, default = nil)
        host.properties.send(property) || fetch(property, default)
      end

      private

      # Helper to fetch a property defined in the capistrano script.
      def fetch(property, default = nil)
        @context.fetch(property, default)
      end

      # Helper to normalize used to multiple configurations keyed by the app name
      # to ensure that the keys are all strings.
      def app_configuration(hash)
        hash ||= {}
        config = {}
        hash.each do |key, value|
          config[key.to_s] = value
        end
        config
      end

      # Translate a list of config file paths into command line arguments for the docker_clusther.sh command.
      def config_args(config_files)
        Array(config_files).collect{ |path| "--config 'config/#{File.basename(path)}'" }
      end

      def app_host_args(app, host)
        global_config_args = config_args(fetch(:docker_configs, nil))
        command_args = Array(fetch(:docker_args, nil))

        host_config_args = config_args(host.properties.send(:docker_configs))
        host_command_args = Array(host.properties.send(:docker_args))

        app_configs = app_configuration(fetch(:docker_app_configs, {}))
        app_args = app_configuration(fetch(:docker_app_args, {}))

        host_app_configs = app_configuration(host.properties.send(:docker_app_configs))
        host_app_args = app_configuration(host.properties.send(:docker_app_args))

        app = app.to_s
        app_config_args = config_args(app_configs[app])
        app_command_args = Array(app_args[app])
        host_app_config_args = config_args(host_app_configs[app])
        host_app_command_args = Array(host_app_args[app])

        inline_app_config_args = config_args(fetch(:"docker_app_configs_#{app}", nil))
        inline_app_command_args = Array(fetch(:"docker_app_args_#{app}", nil))

        host_inline_app_config_args = config_args(host.properties.send(:"docker_app_configs_#{app}"))
        host_inline_app_command_args = Array(host.properties.send(:"docker_app_args_#{app}"))

        args = global_config_args +
               command_args +
               app_config_args +
               inline_app_config_args +
               app_command_args +
               inline_app_command_args +
               host_config_args +
               host_command_args +
               host_app_config_args +
               host_inline_app_config_args +
               host_app_command_args +
               host_inline_app_command_args

        args.uniq
      end
    end
  end
end
