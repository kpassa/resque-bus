# require 'resquebus/tasks'
# will give you the resquebus tasks

namespace :resquebus do
  task :setup

  desc "Subscribes this application to ResqueBus events"
  task :subscribe => [ :preload, :setup ] do
    require 'resque-bus'
    event_queues = ResqueBus.dispatcher.event_queues
    raise "No Queues registered" if event_queues.size == 0
    puts "Registering: #{event_queues.inspect}..."
    ResqueBus.application.subscribe(event_queues)
    puts "...done"
  end
  
  desc "Unsubscribes this application from ResqueBus events"
  task :unsubscribe => [ :preload, :setup ] do
    require 'resque-bus'
    puts "Unsubcribing from ResqueBus..."
    ResqueBus.application.unsubscribe
    puts "...done"
  end
  
  def resquebus_work_queues(queues)
    require 'resque-bus'
    # use the ones for this application
    
    if queues.size == 1
      puts "Working Queue : #{queues.first}"
    else
      puts "Working Queues: #{queues.join(", ")}"
    end
    begin
      worker = Resque::Worker.new(*queues)
      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
      worker.very_verbose = ENV['VVERBOSE']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    if ENV['BACKGROUND']
      unless Process.respond_to?('daemon')
          abort "env var BACKGROUND is set, which requires ruby >= 1.9"
      end
      Process.daemon(true)
    end

    if ENV['PIDFILE']
      File.open(ENV['PIDFILE'], 'w') { |f| f << worker.pid }
    end

    worker.log "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
  
  desc "Start the ResqueBus driver"
  task :driver => [ :preload, :setup ] do
    resquebus_work_queues(["resquebus_incoming"])
  end

  desc "Start a ResqueBus worker"
  task :work => [ :preload, :setup, :subscribe ] do
    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')
    queues = ResqueBus.application.queues if queues.size == 0
    resquebus_work_queues(queues)
  end

  desc "Start multiple ResqueBus workers. Should only be used in dev mode."
  task :workers do
    threads = []

    ENV['COUNT'].to_i.times do
      threads << Thread.new do
        system "rake resquebus:work"
      end
    end

    threads.each { |thread| thread.join }
  end

  # Preload app files if this is Rails
  task :preload => :setup do
    require "resque"
    require "resque-bus"
    
    if defined?(Rails) && Rails.respond_to?(:application)
      # Rails 3
      Rails.application.eager_load!
    elsif defined?(Rails::Initializer)
      # Rails 2.3
      $rails_rake_task = false
      Rails::Initializer.run :load_application_classes
    end
    
    # change the namespace to be the ones used by ResqueBus
    # save the old one for handling later
    ResqueBus.original_redis = Resque.redis
    Resque.redis = ResqueBus.redis
  end
  
  
  # examples to test out the system
  namespace :example do
    desc "Publishes events to example applications"
    task :publish => [ "resquebus:preload", "resquebus:setup" ] do
      which = ["one", "two", "three", "other"][rand(4)]
      ResqueBus.publish("event_#{which}", { "rand" => rand(99999)})
      ResqueBus.publish("event_all", { "rand" => rand(99999)})
      ResqueBus.publish("none_subscribed", { "rand" => rand(99999)})
      puts "published event_#{which}, event_all, none_subscribed"
    end
    
    desc "Sets up an example config"
    task :register => [ "resquebus:preload", "resquebus:setup" ] do
      require 'resque-bus'
      ResqueBus.app_key = "example"
      
      ResqueBus.dispatch do
        subscribe "event_one" do
          puts "event1 happened"
        end

        subscribe "event_two" do
          puts "event2 happened"
        end

        high "event_three" do
          puts "event3 happened (high)"
        end

        low "event_.*" do |attributes|
          puts "LOG ALL: #{attributes.inspect}"
        end
      end
    end
    
    desc "Subscribes this application to ResqueBus example events"
    task :subscribe => [ :register, "resquebus:subscribe" ]
    
    desc "Start a ResqueBus example worker"
    task :work => [ :register, "resquebus:work" ]
    
    desc "Start a ResqueBus example worker"
    task :driver => [ :register, "resquebus:driver" ]
  end
end
