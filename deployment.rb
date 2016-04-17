require 'json'
require 'sinatra'
require 'git'
require 'jekyll'
require 'open3'
require 'yaml'
require 'logger'

set :port, 4251
enable :logging

configuration = YAML.load_file('/etc/active-deployment.yml')
SITES = configuration["sites"]
indent = ""
LOCKS = {}

before do
  env ||= {}
  env['rack.logger'] = Logger.new('/var/log/active-deployment/output.log', 'weekly')
end

not_found do
  'nope'
end

def printOutput(lines, indent, logger)
  lines.each { |line| logger.info indent + line.strip() }
end

def logOutput(response, indent)
  i,o,e,w = response
  val = w.value
  printOutput(o.readlines, indent, logger)
  printOutput(e.readlines, indent, logger)
  i.close
  o.close
  e.close
  if val.exitstatus != 0
    logger.info "  Failed!"
    return
  end
end

def lock(n)
  return false if LOCKS.has_key?(n)
  LOCKS[n] = true
end

def unlock(n)
  LOCKS.delete(n)
end

post '/' do
  push = JSON.parse(params[:payload])
  repo = push["repository"]
  owner = repo["owner"]["name"]
  name = repo["name"]
  if lock(name + '/' + owner)
    deploy(name, owner)
    unlock(name + '/' + owner)
  else
    puts "Unable to obtain deploy lock"
  end
end

get '/:owner/:repo' do
  if deploy(params[:repo], params[:owner])
    "okay"
  else
    "nope"
  end
end

def deploy(name, owner)
  deployed = false
  SITES.each do |site, data|
    if data["repo"] == name and data["username"] == owner
      env = {}
      if data["env"]
        env = data["env"]
      end
      logger.info "Deploying: #{site}"
      begin
        repo = Git.open(data["directory"]) 
        branch = "master"
        user = 'zmbush'
        if data.has_key?("branch")
          branch = data["branch"]
        end
        logger.info "  Fetching most recent changes"
        logOutput(Open3.popen3("cd #{data["directory"]}; sudo -u #{user} git fetch"), "    ")
        logger.info "  Checking out #{branch}"
        logOutput(Open3.popen3("cd #{data["directory"]}; sudo -u #{user} git checkout #{branch}"), "    ")
        logger.info "  Resetting #{branch}"
        logOutput(Open3.popen3("cd #{data["directory"]}; sudo -u #{user} git checkout ."), "    ")
        logger.info "  Merging from origin/#{branch}"
        logOutput(Open3.popen3("cd #{data["directory"]}; sudo -u #{user} git merge origin/#{branch}"), "    ")
        logger.info "  Running Commands:"
        data["commands"].each do |command|
          logger.info "    #{command}"
          logOutput(Open3.popen3(env, "cd #{data["directory"]}; " + command), "      ")
        end
        deployed = true
      rescue Git::GitExecuteError => gee
        logger.info "  Failed to pull..."
        return false
      end
    end
  end
  return deployed
end
