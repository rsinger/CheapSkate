require 'rake/tasklib'
require File.dirname(__FILE__)+'/schema'
module CheapSkate
  class Task < Rake::TaskLib
    attr_accessor :name
    def initialize(name = :cheapskate)
      @name = name

      yield self if block_given?
      define_tasks
    end    

    private
    def define_tasks
      define_help_task
      namespace name do
        define_init_task
        define_convertschema_task
      end
    end  
    
    def define_help_task
      desc "Explains the available commands"
      task "help" do
        puts "Available commands:\n\n"
        puts "\tcheapskate init [project_name] # creates a new CheapSkate instance"
        puts "\tcheapskate convertschema xml=/path/to/schema.xml {yaml=/path/to/output/schema.yml} # converts a schema.xml to schema.yml"
      end
    end  
    
    def define_init_task

      task :init do |t|
        args = ARGV
        raise ArgumentError, "Must supply an project name.  Usage: cheapskate init {project_name}" if args.length < 2
        raise ArgumentError, "Too many arguments supplied.  Usage: cheapskate init {project_name}" if args.length > 2
        raise ArgumentError, "First argument was not 'init' -- how did we get here?!" unless args.first == 'init'
        cwd = Dir.getwd
        project = args[1]
        puts "Create new CheapSkate in #{cwd}/#{project}?  [y/N]"
        STDOUT.flush
        input = STDIN.gets
        input.chomp!
        input = "N" if input !~ /^y$/i
        if input == "N"
          puts "Exiting."
          exit
        else
          if exists = File.exists?("#{cwd}/#{project}")
            puts "A directory already exists at #{cwd}/#{project}!\nExiting."
            exit
          else
            puts "Creating CheapSkate root: #{cwd}/#{project}"
            root = FileUtils.mkdir("#{cwd}/#{project}")
            puts "Creating configuration directory: #{cwd}/#{project}/conf"
            conf = FileUtils.mkdir("#{cwd}/#{project}/conf")
            puts "Creating directory for the Ferret index: #{cwd}/#{project}/db"
            db = FileUtils.mkdir("#{cwd}/#{project}/db")    
            puts "Creating log directory: #{cwd}/#{project}/log"
            db = FileUtils.mkdir("#{cwd}/#{project}/log")
            puts "Creating public directory: #{cwd}/#{project}/public"
            db = FileUtils.mkdir("#{cwd}/#{project}/public")    
            config = {project.to_sym=>{:ferret=>{:path=>"db/skate"}, :facet_score_threshold=>0.0, :schema=>"conf/schema.yml"}}
            puts "Writing default cheapskate.yml"
            cs_yml = open("#{cwd}/#{project}/conf/cheapskate.yml", "w")
            cs_yml << config.to_yaml
            cs_yml.close
            schema = {"schema"=>{"name"=>"example", "copyFields"=>[{"cat"=>"text"}, {"name"=>"text"}, {"manu"=>"text"}, {"features"=>"text"}, {"includes"=>"text"}, {"manu"=>"manu_exact"}], "fields"=>{"name"=>{"stored"=>true, "indexed"=>true, "type"=>"textgen"}, "cat"=>{"stored"=>true, "multiValued"=>true, "indexed"=>true, "type"=>"text_ws", "omitNorms"=>true}, "price"=>{"stored"=>true, "indexed"=>true, "type"=>"float"}, "popularity"=>{"stored"=>true, "indexed"=>true, "type"=>"int"}, "category"=>{"stored"=>true, "indexed"=>true, "type"=>"textgen"}, "includes"=>{"termOffsets"=>true, "stored"=>true, "indexed"=>true, "termVectors"=>true, "type"=>"text", "termPositions"=>true}, "title"=>{"stored"=>true, "multiValued"=>true, "indexed"=>true, "type"=>"text"}, "comments"=>{"stored"=>true, "indexed"=>true, "type"=>"text"}, "author"=>{"stored"=>true, "indexed"=>true, "type"=>"textgen"}, "content_type"=>{"stored"=>true, "multiValued"=>true, "indexed"=>true, "type"=>"string"}, "weight"=>{"stored"=>true, "indexed"=>true, "type"=>"float"}, "text"=>{"stored"=>false, "multiValued"=>true, "indexed"=>true, "type"=>"text"}, "id"=>{"required"=>true, "stored"=>true, "indexed"=>true, "type"=>"string"}, "subject"=>{"stored"=>true, "indexed"=>true, "type"=>"text"}, "text_rev"=>{"stored"=>false, "multiValued"=>true, "indexed"=>true, "type"=>"text_rev"}, "sku"=>{"stored"=>true, "indexed"=>true, "type"=>"textTight", "omitNorms"=>true}, "features"=>{"stored"=>true, "multiValued"=>true, "indexed"=>true, "type"=>"text"}, "links"=>{"stored"=>true, "multiValued"=>true, "indexed"=>true, "type"=>"string"}, "manu_exact"=>{"stored"=>false, "indexed"=>true, "type"=>"string"}, "inStock"=>{"stored"=>true, "indexed"=>true, "type"=>"boolean"}, "description"=>{"stored"=>true, "indexed"=>true, "type"=>"text"}, "alphaNameSort"=>{"stored"=>false, "indexed"=>true, "type"=>"alphaOnlySort"}, "manu"=>{"stored"=>true, "indexed"=>true, "type"=>"textgen", "omitNorms"=>true}, "last_modified"=>{"stored"=>true, "indexed"=>true, "type"=>"date"}, "payloads"=>{"stored"=>true, "indexed"=>true, "type"=>"payloads"}, "keywords"=>{"stored"=>true, "indexed"=>true, "type"=>"textgen"}}, "uniqueKey"=>"id", "version"=>"1.2", "types"=>{"pint"=>{:type=>:int, :index=>:untokenized_omit_norms}, "boolean"=>{:type=>:bool, :index=>:untokenized_omit_norms}, "tfloat"=>{:type=>nil, :index=>:untokenized_omit_norms}, "tdate"=>{:type=>nil, :index=>:untokenized_omit_norms}, "sfloat"=>{:type=>nil, :index=>:untokenized_omit_norms}, "phonetic"=>{:type=>:text}, "plong"=>{:type=>nil, :index=>:untokenized_omit_norms}, "pfloat"=>{:type=>:float, :index=>:untokenized_omit_norms}, "pdouble"=>{:type=>nil, :index=>:untokenized_omit_norms}, "binary"=>{:type=>nil, :index=>:untokenized}, "int"=>{:type=>nil, :index=>:untokenized_omit_norms}, "text"=>{:type=>:text}, "lowercase"=>{:type=>:text}, "date"=>{:type=>nil, :index=>:untokenized_omit_norms}, "sint"=>{:type=>nil, :index=>:untokenized_omit_norms}, "slong"=>{:type=>nil, :index=>:untokenized_omit_norms}, "text_rev"=>{:type=>:text}, "tint"=>{:type=>nil, :index=>:untokenized_omit_norms}, "tlong"=>{:type=>nil, :index=>:untokenized_omit_norms}, "tdouble"=>{:type=>nil, :index=>:untokenized_omit_norms}, "random"=>{:type=>nil, :index=>:untokenized}, "text_ws"=>{:type=>:text}, "textgen"=>{:type=>:text}, "string"=>{:type=>:string, :index=>:untokenized_omit_norms}, "double"=>{:type=>nil, :index=>:untokenized_omit_norms}, "pdate"=>{:type=>:date, :index=>:untokenized_omit_norms}, "sdouble"=>{:type=>nil, :index=>:untokenized_omit_norms}, "alphaOnlySort"=>{:type=>:text, :index=>:omit_norms}, "payloads"=>{:type=>:text}, "ignored"=>{:type=>:string, :index=>:untokenized}, "float"=>{:type=>nil, :index=>:untokenized_omit_norms}, "long"=>{:type=>nil, :index=>:untokenized_omit_norms}, "textTight"=>{:type=>:text}}, "dynamic_fields"=>{"*_tf"=>{"stored"=>true, "indexed"=>true, "type"=>"tfloat"}, "*_l"=>{"stored"=>true, "indexed"=>true, "type"=>"long"}, "*_b"=>{"stored"=>true, "indexed"=>true, "type"=>"boolean"}, "*_ti"=>{"stored"=>true, "indexed"=>true, "type"=>"tint"}, "random_*"=>{"type"=>"random"}, "*_d"=>{"stored"=>true, "indexed"=>true, "type"=>"double"}, "*_f"=>{"stored"=>true, "indexed"=>true, "type"=>"float"}, "*_tl"=>{"stored"=>true, "indexed"=>true, "type"=>"tlong"}, "*_tdt"=>{"stored"=>true, "indexed"=>true, "type"=>"tdate"}, "*_pi"=>{"stored"=>true, "indexed"=>true, "type"=>"pint"}, "*_s"=>{"stored"=>true, "indexed"=>true, "type"=>"string"}, "attr_*"=>{"stored"=>true, "multiValued"=>true, "indexed"=>true, "type"=>"textgen"}, "*_i"=>{"stored"=>true, "indexed"=>true, "type"=>"int"}, "*_t"=>{"stored"=>true, "indexed"=>true, "type"=>"text"}, "*_dt"=>{"stored"=>true, "indexed"=>true, "type"=>"date"}, "*_td"=>{"stored"=>true, "indexed"=>true, "type"=>"tdouble"}, "ignored_*"=>{"multiValued"=>true, "type"=>"ignored"}}, "defaultSearchField"=>"text"}}
            puts "Writing default schema.yml"
            s_yml = open("#{cwd}/#{project}/conf/schema.yml", "w")
            s_yml << schema.to_yaml
            s_yml.close  
            puts "Writing default rackup file at #{cwd}/#{project}/config.ru"
            rackup = open("#{cwd}/#{project}/config.ru", "w")      
            rackup_body =<<END
require 'rubygems'
require 'sinatra'

root_dir = File.dirname(__FILE__)

set :environment, :production
set :configuration, root_dir+"/conf/cheapskate.yml"
set :site, :#{project}
set :root,  root_dir

set :logging, false
disable :run

FileUtils.mkdir_p 'log' unless File.exists?('log')
log = File.new("log/\#{Sinatra::Application.site}.log", "a")
STDOUT.reopen(log)
STDERR.reopen(log)
require 'cheap_skate'
run CheapSkate::Application

END
            rackup << rackup_body
            rackup.close
          end
        end
      end

    end
        
    def define_convertschema_task
      desc "Parses a Solr schema.xml document and outputs a CheapSkate schema.yml.  Needs the arguments xml=/path/to/schema.xml Defaults to ./conf/schema.yml, use the yaml= argument to specify the output."
      task "convertschema" do
        raise ArgumentError, "No schema.xml specified.  Usage: cheapskate convertschema xml=/path/to/schema.xml" unless ENV['xml']
        xml = open(ENV['xml'],'r')
        yml = CheapSkate::Schema.xml_to_yaml(xml)
        if ENV['yaml']
          puts "Writing #{ENV['xml']} out to #{ENV['yaml']}."
          outfile = open(ENV['yaml'],'w')
        else
          puts "Writing #{ENV['xml']} out to ./conf/schema.yml."          
          outfile = open('./conf/schema.yml','w')
        end
        outfile << yml.to_s
        outfile.close
      end
    end    
  end
end
