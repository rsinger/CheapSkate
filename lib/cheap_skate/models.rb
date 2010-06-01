module CheapSkate
  class Document < Ferret::Document
    attr_accessor :index, :doc_id
    def initialize(doc_id=UUID.generate, boost=1.0)
      @doc_id = doc_id
      super(boost)
    end

    
    def add_field(key, value)
      @index.set_dynamic_field(key.to_sym) unless @index.schema.field_names.index(key.to_sym)
      if value.is_a?(Array)
        value.each do |v|
          add_field(key, v)
        end
      else      
        self[key.to_sym] ||= []
        self[key.to_sym] << value
      end
      if copy_fields = @index.schema.copy_fields[key.to_sym]
        copy_fields.each do |field|
          add_field(field, value)
        end
      end
    end  
  end  
  
  class ResultSet
    attr_accessor :total, :docs, :query, :limit, :offset, :facets, :query_time, :nl_format
    def <<(obj)
      @docs ||=[]
      @docs << obj
    end
  
    def to_hash()
      response = {"responseHeader"=>{"status"=>0, "QTime"=>self.query_time, "params"=>{"q"=>self.query, "version"=>"2.2", "rows"=>self.limit}}}
      response["response"] = {"numFound"=>self.total, "start"=>self.offset, "docs"=>[]}
      if self.docs
        self.docs.each do |doc|
          response["response"]["docs"] << doc
        end
      end
      
      response
    end    
  
    def as_ruby
      response = self.to_hash
      response["responseHeader"]["wt"] = "ruby"
      response.inspect
    end    
    def as_json
      response = self.to_hash
      response["responseHeader"]["wt"] = "json"
      response.to_json
    end
  end
  
  module Facet
    attr_accessor :facet_queries, :facet_limit, :facet_fields, :facet_offset, :facets, :facet_total
    def add_facets_to_query(params)

      if params['facet.limit'] && !params['facet.limit'].empty?
        @facet_limit = params['facet.limit'].first.to_i
      else
        @facet_limit = 10
      end
      if params['facet.offset'] && !params['facet.offset'].empty?
        @facet_offset = params['facet.offset'].first.to_i
      else
        @facet_offset = 0
      end

      @facet_fields = {}
      params["facet.field"].each do | field |
        @facet_fields[field.to_sym] = {}
      end      

      @filter_proc = lambda do |doc,score,searcher|
        @facet_fields.keys.each do |field|
          [*searcher[doc][field]].each do |term|  
            next if term.nil?
            @facet_fields[field][term] ||=0
            @facet_fields[field][term] += 1
          end
        end
      end
      
    end
    
    def add_facet_query(query, query_string)
      @facet_queries ||= []
      @facet_queries << {:query=>query, :results=>0, :query_string=>query_string}
    end
    
    def add_facets_to_results(query)

      @facet_fields = query.facet_fields
      @facet_limit = query.facet_limit
      @facet_queries = query.facet_queries
      @facet_offset = query.facet_offset
    end
    
    def format_facets      
      case self.nl_format
      when "flat" then flatten_facet_array
      when "map" then map_facet_array
      else @facet_fields
      end      
    end      
    
    def flatten_facet_array
      flat_arr = {}
      @facet_fields.each_pair do |k,v|
        flat_arr[k] = v.flatten
      end
      flat_arr
    end
    
    def map_facet_array
      map_arr = {}
      @facet_fields.each_pair do |k,v|
        map_arr[k] ||= {}
        v.flatten.each_cons(2) do |key, val|
         map_arr[k][key] = val
       end
      end
      map_arr      
    end
    
    def parse_facet_query(params)     
     [*params['facet.query']].each do |q|
        next unless q
        bool = Ferret::Search::BooleanQuery.new
      
 
        (idx, term) = q.split(":")
        term.sub!(/^\"/,'').sub!(/\"$/,'')
        bool.add_query(Ferret::Search::TermQuery.new(idx.to_sym, term), :must)        
 
        unless bool.to_s.empty?
          if @filter
            bool = Ferret::Search::FilteredQuery(bool, @filter)
          end
          query.query = @query
          query.filter = Ferret::Search::QueryFilter.new(bool)
          add_facet_query(query, q)
        end
      end      

    end 
    
    def to_hash
      r = super
      p = r["responseHeader"]["params"]
      p["facets"] = "true"
      p["facet.field"] = @fields
      p["facet.limit"] = @limit
      p["facet.offset"] = @offset
      p["facet.query"] = @query
      @total = 400;
      r["facet_counts"] = {"facet_fields"=>format_facets, "facet_queries"=>[]}
      if @facet_queries
        @facet_queries.each do | fq |
          r["facet_counts"]["facet_queries"] << [fq[:query_string], fq[:results]]
        end
      end
      r      
    end   
    
  end



class FacetResponse
  attr_accessor :query, :limit, :fields, :offset, :facets, :total
  def initialize
    @fields = []
    @facets = {}
  end
  
  def add_facets(r)

  end
end
  
  class InputDocument
    attr_reader :doc
    attr_accessor :query_time
    def initialize(doc, index)
      doc.sub!(/^[^\<]*/,'')
      @doc = Hpricot::XML(doc)
      @index = index
    end
  
    def parse
      action = @doc.root.name
      self.send(action)
    end
  
    def add
      (@doc/'/add/doc').each do |doc|
        document = @index.create_document
        (doc/'field').each do |elem|
          field = elem.attributes['name']
          value = nil
          value = elem.inner_html
          if field and value
            if field == "id"
              document[@index.schema.id_field] = value
            else
              document.add_field(field, value)
            end
          end
        end      
        @index << document
      end
    end
  
    def commit
      @index.flush
    end
  
    def delete
      ids = []
      (@doc/"/delete/id").each do |del|
        ids << del.inner_html
      end
      (@doc/"/delete/query").each do |del|
        @index.search_each(del.attributes['q'], :limit=>:all) do |id,score|
          ids << id
        end      
      end
      unless ids.empty?
        @index.delete(ids)
      end
    end
  
    def optimize
      @index.optimize
    end
  
    def to_hash
      return {"responseHeader"=>{"QTime"=>self.query_time, "status"=>0}}
    end
  
    def as_ruby
      return to_hash.inspect
    end
  
    def as_json
      return to_hash.to_json    
    end
  end


  class CSVLoader
    attr_reader :fields, :filename, :file, :field_meta
    def initialize(params, index)
      @filename = params['stream.file']
      if @filename
        @file = open(@filename)
      end
      @field_meta = {}
      params.each_pair do |key, val|
        next unless key =~ /^f\./
        (f,field,arg) = key.split(".")
        @field_meta[field] ||={}
        @field_meta[field][arg] = val
      end
      @index = index
    end
  
    def parse
      if @file
        parse_file
      end
    end
  
    def parse_file
      @fields = @file.gets.chomp.split(",")
      documents = []
      while line = @file.gets
        line.chomp!
        doc = @index.create_document
        # keep track of where we are on the row
        i = 0
        FasterCSV.parse_line(line).each do |field|
          unless field && @fields[i]
            i+= 1
            next
          end
          if @fields[i] == "id"
            doc[@index.schema.id_field] = field.strip
          else
            if @field_meta[@fields[i]] && @field_meta[@fields[i]]["split"] == "true"
              field.split(@field_meta[@fields[i]]["separator"]).each do |f|
                doc.add_field(@fields[i], f.strip)
              end
            else
              doc.add_field(@fields[i], field.strip)
            end
          end        
          i+=1
        end  
        @index << doc    
      end
    end
  end

  class Query
    attr_accessor :parser, :query, :filter, :filter_proc  
  end
end