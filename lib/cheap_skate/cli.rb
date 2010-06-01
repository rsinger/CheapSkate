require 'rake'
require 'yaml'
require 'fileutils'
require File.dirname(__FILE__)+'/tasks'

module CheapSkate
  class CLI < Rake::Application
    def initialize
      super
    end
    def load_rakefile
      @name = 'cheapskate'

      # Load the main warbler tasks
      CheapSkate::Task.new

      task :default => :help

      desc "Create a new CheapSkate instance"
      task :init => "cheapskate:init"

      desc "Convert a Solr schema.xml to CheapSkate schema.yml"
      task :convertschema => "cheapskate:convertschema"

    end

    # Loads the project Rakefile in a separate application
    def load_project_rakefile
      Rake.application = Rake::Application.new
      Rake::Application::DEFAULT_RAKEFILES.each do |rf|
        if File.exist?(rf)
          load rf
          break
        end
      end
      Rake.application = self
    end

    # Run the application: The equivalent code for the +warble+ command
    # is simply <tt>Warbler::Application.new.run</tt>.
    def run
      Rake.application = self
      super
    end  
  end

end

