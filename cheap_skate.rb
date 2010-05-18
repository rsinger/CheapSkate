require "rubygems"
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
require 'lib/schema'
require 'faster_csv'

configure do
  env = Sinatra::Application.environment().to_sym
  CONFIG = YAML.load_file('conf/cheapskate.yml')[env]
  Index = Struct.new(:index, :schema)
  
  i = Ferret::Index::Index.new(CONFIG[:ferret]||{})
  yaml = YAML.load_file(CONFIG[:schema])
  s = Schema.new
  s.load_from_conf(yaml)
  infos = i.field_infos
  index_schema_changed = false
  s.field_names.each do |fld|
    f = s.field_to_field_info(fld)
    if !infos[f.name]
      infos << f
      index_schema_changed = true
    end
  end
  if index_schema_changed && i.reader.num_docs > 0
    raise "Schema has changed, but Index has data!"
  elsif index_schema_changed
    puts "Creating schema at #{CONFIG[:ferret][:path]}"
    infos.create_index(CONFIG[:ferret][:path])
  end
  CheapSkate = Index.new(i,s)
  puts "CheapSkate starting with index shema: #{yaml["schema"]["name"]}"
  puts "#{CheapSkate.index.reader.num_docs} documents currently indexed."
  puts CONFIG.inspect
end
  


get '/select/' do
  results = select(params)
  wt = params["wt"] || "json"
  results.query_time = qtime
  if wt == "json"
    content_type 'application/json', :charset => 'utf-8'
  end
  results.send("as_#{wt}")
end

post '/select/' do
  results = select(params)
  wt = params["wt"] || "json"
  results.query_time = qtime
  results.send("as_#{wt}")
end

get '/update/csv/' do
  csv = CSVLoader.new(params)
  csv.parse
out = <<END
  <?xml version="1.0" encoding="UTF-8"?>
  <response>
  <lst name="responseHeader"><int name="status">0</int><int name="QTime">#{qtime}</int></lst>
  </response>
END
end

post '/update/' do
  i = InputDocument.new(request.env["rack.input"].read)
  i.parse
  wt = params["wt"] || "json"
  i.query_time = qtime
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
    qry = request.env["rack.input"].read
    if qry.empty?
      qry = request.env["rack.request.query_string"]
    end

    parm = CGI.parse(qry)

    query = Query.new(parm["q"], parm["fq"])

    opts = {}
    opts[:offset] = (params["start"] || 0).to_i
    opts[:limit] = (params["rows"] || 10).to_i
    if params["sort"]
      opts[:sort] = params["sort"]
      opts[:sort].sub!(/ asc/,"")
      opts[:sort].sub!(/ desc/,"DESC")
    end

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
