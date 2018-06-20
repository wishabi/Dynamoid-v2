require 'dynamoid'
require 'dynamoid/tasks/database'

namespace :dynamoid do
  desc "Creates DynamoDB tables, one for each of your Dynamoid models - does not modify pre-existing tables"
  task :create_tables => :environment do
    # Load models so Dynamoid will be able to discover tables expected.
    Dir[ File.join(Dynamoid::Config.models_dir, "*.rb") ].sort.each { |file| require file }
    if Dynamoid.included_models.any?
      tables = Dynamoid::Tasks::Database.create_tables
      result = tables[:created].map{ |c| "#{c} created" } + tables[:existing].map{ |e| "#{e} already exists" }
      result.sort.each{ |r| puts r }
    else
      puts "Dynamoid models are not loaded, or you have no Dynamoid models."
    end
  end

  desc 'Tests if the DynamoDB instance can be contacted using your configuration'
  task :ping => :environment do
    success = false
    failure_reason = nil

    begin
      Dynamoid::Tasks::Database.ping
      success = true
    rescue Exception => e
      failure_reason = e.message
    end

    msg = "Connection to DynamoDB #{success ? 'OK' : 'FAILED'}"
    msg << if Dynamoid.config.endpoint
             " at local endpoint '#{Dynamoid.config.endpoint}'"
           else
             ' at remote AWS endpoint'
           end
    if not success
      msg << ", reason being '#{failure_reason}'"
    end
    puts msg
  end
end
