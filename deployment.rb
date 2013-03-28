require 'json'
require 'sinatra'
require 'git'
require 'jekyll'
require 'open3'
require 'yaml'

set :port, 4251

configuration = YAML.load_file('/etc/active-deployment.yml')
sites = configuration["sites"]

not_found do
  'nope'
end

post '/' do
  push = JSON.parse(params[:payload])
  repo = push["repository"]
  owner = repo["owner"]["name"]
  name = repo["name"]
  sites.each do |site, data|
    if data["repo"] == name and data["username"] == owner
      puts "Deploying: #{site}"
      Dir.chdir(data["directory"]) do
        puts "  Pulling changes..."
        begin
          repo = Git.open(data["directory"]) 
          repo.remote('origin').fetch
          repo.remote('origin').merge
          puts "  Running Commands:"
          data["commands"].each do |command|
            puts "    #{command}"
            stdin, stdout, stderr, wait_thr = Open3.popen3(command)
            wait_thr.value
            stdin.close
            stdout.close
            stderr.close
          end
        rescue Git::GitExecuteError => gee
          puts "  Failed to pull..."
        end
      end
    end
  end
end
