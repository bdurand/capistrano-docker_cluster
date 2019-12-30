# frozen_string_literal: true

require 'capistrano/scm/none'

require_relative "docker_cluster/version"
require_relative "docker_cluster/scripts"

load File.expand_path("tasks/docker_cluster.rake", __dir__)

install_plugin Capistrano::Scm::None::Plugin