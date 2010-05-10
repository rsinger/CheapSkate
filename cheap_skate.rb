require "rubygems"
require "dm-core" 
require "uuid"
require 'ferret'
require 'json'
require 'jcode'
require 'hpricot'
$KCODE = 'u'
require 'cgi'
require 'sinatra'
require 'yaml'
require 'lib/models'

configure :development do
  CONFIG = YAML.load_file('conf/cheapskate.yml')[:development]
end

configure :production do
  CONFIG = YAML.load_file('conf/cheapskate.yml')[:production]
end

configure do
  INDEX = Ferret::Index::Index.new(CONFIG[:ferret]||{})
  
  DataMapper.setup(:default, CONFIG[:database])
  DocumentField.auto_upgrade! if DocumentField.respond_to?(:"auto_upgrade!")
end
  


get '/select/' do
  results = select(params)
  wt = params["wt"] || "json"
  results.query_time = qtime
  results.send("as_#{wt}")
end

post '/select/' do
  results = select(params)
  wt = params["wt"] || "json"
  results.query_time = qtime
  results.send("as_#{wt}")
end

get '/update/csv/' do
  puts params.inspect
end

post '/update/' do
  i = InputDocument.new(request.env["rack.input"].read)
  i.parse
  wt = params["wt"] || "json"
  results.query_time = qtime
  i.send("as_#{wt}")
end

get '/admin/ping/' do
  '<response>
  <lst name="responseHeader"><int name="status">0</int><int name="QTime">1</int><lst name="params"><str name="echoParams">all</str><str name="echoParams">all</str><str name="q">solrpingquery</str><str name="qt">standard</str></lst></lst><str name="status">OK</str>
  </response>'
end

before do
  if CONFIG[:prefix_path]
    request.path_info.sub!(/^#{CONFIG[:prefix_path]}/,'')
  end
  unless request.path_info[-1,1] == "/"
    request.path_info << "/"
  end
  @time = Time.now
end

helpers do
  def select(params)
    qry=request.env["rack.input"].read
    parm = CGI.parse(qry)
    query = params[:q]
    if parm['fq'] && !parm['fq'].empty?
      parm['fq'].each do |fq|
        query << " +#{fq}"
      end
    end
    if !parm['facet.query'] or parm['facet.query'].empty?
      parm['facet.query'] = [query]
    end
    opts = {}
    opts[:offset] = params["start"] || 0
    opts[:limit] = params["rows"] || 10  
    results = Document.search(query, opts)
    if params["facet"] == "true"
      results.facets = Facet.search(parm)
    end
    results
  end
  
  def qtime
     ((Time.now - @time) * 1000).to_i    
   end
end
