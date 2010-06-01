module CheapSkate
  class Application < Sinatra::Base

    configure do

      config = YAML.load_file(Sinatra::Application.configuration)[Sinatra::Application.site]

      i = CheapSkate::Index.new(config[:ferret]||{}, Schema.new_from_config(YAML.load_file(config[:schema])))
      i.set_fields_from_schema
      set :index, i
      set :prefix_path, (config[:prefix_path]||nil)
      STDOUT.puts "CheapSkate starting with index schema: #{i.schema.name}"
      STDOUT.puts  "#{i.reader.num_docs} documents currently indexed."
    end
  
    get '/' do
      "Welcome to CheapSkate"
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
      csv = CSVLoader.new(params, settings.index)
      csv.parse
    out = <<END
      <?xml version="1.0" encoding="UTF-8"?>
      <response>
      <lst name="responseHeader"><int name="status">0</int><int name="QTime">#{qtime}</int></lst>
      </response>
END
    end

    post '/update/' do
      i = InputDocument.new(request.env["rack.input"].read, settings.index)
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
      if options.prefix_path
        request.path_info.sub!(/^#{options.prefix_path}/,'')
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
        qt = (params['qt'] || "standard")
        query = settings.index.send("parse_#{qt}_query".to_sym, parm)

        opts = {}
        opts[:offset] = (params["start"] || 0).to_i
        opts[:limit] = (params["rows"] || 10).to_i
        if params["sort"]
          opts[:sort] = params["sort"]
          opts[:sort].sub!(/ asc/,"")
          opts[:sort].sub!(/ desc/,"DESC")
        end
        if params["facet"] == "true"
          query.extend(Facet)
          query.add_facets_to_query(parm)  
          query.parse_facet_query(parm)        
        end
        results = settings.index.search(query, opts)
        results
      end
  
      def qtime
         ((Time.now - @time) * 1000).to_i    
       end
    end
  end
end