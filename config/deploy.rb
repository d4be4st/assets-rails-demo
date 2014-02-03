require 'mina/bundler'
require 'mina/rails'
require 'mina/git'
#require 'mina/whenever' # uncomment if using whenever

# Setup project
# - mina production setup
# Deploy project
# - mina production deploy
# Tail log from project
# - mina prodution log
# Pull data from production
# - mina production data:pull

set :repository, 'git@codebasehq.com:test/test/test.git'
set :user, 'www-data'

task :production do
  set :domain, 'assets.hadjic.com'
  set :deploy_to, '/var/www/a/assets.hadjic.com'
  set :rails_env, 'production'
  set :branch, 'master'
end


##################################################################################
########################## DO NOT EDIT THE CODE BELOW ############################
##################################################################################

set :shared_paths, ['log']

task :deploy => :stages do
  deploy do
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'
    invoke :'deploy:cleanup'
    #invoke :'whenever:update' # uncomment if using whenever

    to :launch do
      # Capistrano to Mina Fix, symlink system to shared
      queue! %[echo "-----> Symlink system to shared"]
      queue! %[ln -nFs #{deploy_to}/shared/system #{deploy_to}/#{current_path}/public/system]

      invoke :restart_application
      invoke :ping_application
    end
  end
end

# First ensure that the stage is selected
task :stages do
  unless domain
    print_error "A server needs to be specified. e.g. production/staging"
    exit
  end
end

# Just overwrote to execute stages first
task :setup => :stages do
  queue! %[mkdir -p "#{deploy_to}/shared/log"]
  queue! %[chmod g+rx,u+rwx "#{deploy_to}/shared/log"]
end

# Tail log from server
task :log => :stages do
  queue "tail -f #{deploy_to}/#{current_path}/log/#{rails_env}.log"
end

# Restart application after deployment
task :restart_application do
  queue %[echo "-----> Restarting application"]
  queue "mkdir -p #{deploy_to}/#{current_path}/tmp"
  queue "touch #{deploy_to}/#{current_path}/tmp/restart.txt"
end

# Ping application
task :ping_application do
  queue %[echo "-----> Ping domain"]
  queue %[curl -s #{domain} > /dev/null]
end

# Sync database
RYAML = <<-BASH
  function ryaml {
    ruby -ryaml -e 'puts ARGV[1..-1].inject(YAML.load(File.read(ARGV[0]))) {|acc, key| acc[key] }' "$@"
  };
BASH

namespace :data do
  task :pull => :stages do
    isolate do
      queue RYAML
      queue "HOST=$(ryaml #{deploy_to}/#{current_path}/config/database.yml #{rails_env} host)"
      queue "DATABASE=$(ryaml #{deploy_to}/#{current_path}/config/database.yml #{rails_env} database)"
      queue "USERNAME=$(ryaml #{deploy_to}/#{current_path}/config/database.yml #{rails_env} username)"
      queue "PASSWORD=$(ryaml #{deploy_to}/#{current_path}/config/database.yml #{rails_env} password)"
      queue "mysqldump $DATABASE --host=$HOST --user=$USERNAME --password=$PASSWORD > #{deploy_to}/dump.sql"
      queue "gzip -f #{deploy_to}/dump.sql"

      mina_cleanup!
    end

    %x[scp #{user}@#{domain}:#{deploy_to}/dump.sql.gz .]
    %x[gunzip -f dump.sql.gz]
    %x[#{RYAML} mysql --verbose --user=$(ryaml config/database.yml development username) --password=$(ryaml config/database.yml development password) $(ryaml config/database.yml development database) < dump.sql]
    %x[rm dump.sql]
  end
end