class Document < Ferret::Document
  
  def initialize(doc_id=UUID.generate, boost=1.0)
    self[CheapSkate.schema.id_field] = doc_id
    super(boost)
  end
    
  #def to_document(stringify_keys=false)
  #  id_field = :id
  #  id_field = "id" if stringify_keys
  #  document = {id_field=>@document_id}
  #  self.each_pair do |key, val|
  #    next unless key
  #    if stringify_keys
  #      document[key.to_s] = val
  #    else
  #      document[key.to_sym] = val
  #    end
  #  end
  #  document
  #end
  
  def delete(clear=true)
    CheapSkate.index.delete(self.document_id)
    self.clear if clear
  end
  
  
  def self.delete(ids)
    [*ids].each do |id|
      CheapSkate.index.delete(id)     
    end
  end
    
  def add_field(key, value)
    CheapSkate.schema.set_dynamic_field(key.to_sym) unless CheapSkate.schema.field_names.index(key.to_sym)
    if value.is_a?(Array)
      value.each do |v|
        add_field(key, v)
      end
    else      
      self[key.to_sym] ||= []
      self[key.to_sym] << value
    end
    if copy_fields = CheapSkate.schema.copy_fields[key.to_sym]
      copy_fields.each do |field|
        add_field(field, value)
      end
    end
  end
  
  def self.search(query, opts={})
    results = ResultSet.new
    results.offset = opts[:offset]
    results.limit = opts[:limit]
    results.query = query.query.to_s
    if opts[:limit] < 1
      opts[:limit] = 1
    end
    if query.filter
      opts[:filter] = query.filter
    end

    results.total = CheapSkate.index.search_each(query.query, opts) do |id, score|
      results << CheapSkate.schema.typed_document(CheapSkate.index[id])
    end
    results
  end
  
  def self.typed_document(untyped_doc, field_types)
    doc = self.new(untyped_doc[:id])
    untyped_doc.fields.each do |field|
      [*untyped_doc[field]].each do |val|
        value = case field_types[field]
        when "String" then val
        when "Fixnum" then val.to_i
        when "Bignum" then val.to_i          
        when "Float" then val.to_f
        when "Time" then Time.parse(val)
        when "Date" then Date.parse(val)
        when "DateTime" then DateTime.parse(val)
        when "TrueClass" then true
        when "FalseClass" then false
        when "NilClass" then nil
        else
          # Not sure what it is, but we don't support it.
          val
        end
        if doc[field]
          doc[field] = [*doc[field]]
          doc[field] << val
        else
          doc[field] = val
        end
      end
    end
    doc
  end
  
end  
  
class ResultSet
  attr_accessor :total, :docs, :query, :limit, :offset, :facets, :query_time
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
    @facets.add_facets(response) if @facets
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

class Facet
  def self.search(params)
    response = FacetResponse.new
    if params['facet.query'] && !params['facet.query'].empty?
      response.query = params['facet.query'].first
      query = Query.new(params['facet.query'].first)
    else
      query = Query.new(params['q'], params['fq'])
    end

    ids = []
    
    # No point in grabbing everything here.

    if params['facet.limit'] && !params['facet.limit'].empty?
      response.limit = params['facet.limit'].first.to_i
    else
      response.limit = 10
    end
    if params['facet.offset'] && !params['facet.offset'].empty?
      response.offset = params['facet.offset'].first.to_i
    else
      response.offset = 0
    end
    

    facet_fields = {}
    params["facet.field"].each do | field |
      facet_fields[field.to_sym] = {}
      response.fields << field
    end

    # Make sure your facet fields are untokenized otherwise you'll get ugly results here
    unless query.query.is_a?(Ferret::Search::MatchAllQuery) && query.filter.nil?
      facet_filter = lambda do |doc,score,searcher|
        # You must be this high to be a good facet
        return if score < CONFIG[:facet_score_threshold]
        facet_fields.keys.each do |field|
          [*searcher[doc][field]].each do |term|  
            next if term.nil?
            facet_fields[field][term] ||=0
            facet_fields[field][term] += 1
          end
        end
      end

      response.total = CheapSkate.index.search_each(query.query, :filter=>query.filter, :limit=>:all, :filter_proc=>facet_filter) do |id, score|
      end
    else
      facet_fields.keys.each do |field|
        CheapSkate.index.reader.terms(field).each do |term, count|
          facet_fields[field][term] = count
        end
      end
    end

    facet_fields.each do | facet, values |
      response.facets[facet] = values.sort{|a,b| b[1]<=>a[1]}[response.offset, response.limit]
    end

    response
  end
end

class FacetResponse
  attr_accessor :query, :limit, :fields, :offset, :facets, :total
  def initialize
    @fields = []
    @facets = {}
  end
  
  def add_facets(r)
    p = r["responseHeader"]["params"]
    p["facets"] = "true"
    p["facet.field"] = @fields
    p["facet.limit"] = @limit
    p["facet.offset"] = @offset
    p["facet.query"] = @query
    @total = 400;
    r["facet_counts"] = {"facet_queries"=>{@query=>@total}, "facet_fields"=>@facets}
  end
end
  
class InputDocument
  attr_reader :doc
  attr_accessor :query_time
  def initialize(doc)
    doc.sub!(/^[^\<]*/,'')
    @doc = Hpricot::XML(doc)
  end
  
  def parse
    action = @doc.root.name
    self.send(action)
  end
  
  def add
    (@doc/'/add/doc').each do |doc|
      document = Document.new
      (doc/'field').each do |elem|
        field = elem.attributes['name']
        value = nil
        value = elem.inner_html
        if field and value
          if field == "id"
            document[CheapSkate.schema.id_field] = value
          else
            document.add_field(field, value)
          end
        end
      end      
      CheapSkate.index << document
    end
  end
  
  def commit
    CheapSkate.index.flush
  end
  
  def delete
    ids = []
    (@doc/"/delete/id").each do |del|
      ids << del.inner_html
    end
    (@doc/"/delete/query").each do |del|
      CheapSkate.index.search_each(del.attributes['q'], :limit=>:all) do |id,score|
        ids << id
      end      
    end
    unless ids.empty?
      Document.delete(ids)
    end
  end
  
  def optimize
    CheapSkate.index.optimize
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
  def initialize(params)
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
  end
  
  def parse
    if @file
      parse_file
    end
  end
  
  def parse_file
    @fields = @file.gets.chomp.split(",")
    while line = @file.gets
      line.chomp!
      doc = Document.new
      # keep track of where we are on the row
      i = 0
      FasterCSV.parse_line(line).each do |field|
        unless field && @fields[i]
          i+= 1
          next
        end
        if @fields[i] == "id"
          doc[:id] = field
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
      CheapSkate.index << doc    
    end
  end
end

class Query
  attr_accessor :parser, :query, :filter
  def initialize(query, filter_queries=nil)
    init_parser
    if query && !query.empty? && query != "*:*"
      @query = @parser.parse(query)
    else
      @query = Ferret::Search::MatchAllQuery.new
    end
    if filter_queries
      bool = Ferret::Search::BooleanQuery.new
      [*filter_queries].each do |fq|
        if (filtq = @strict_parser.parse(fq) && !filtq.to_s.empty?)
          bool << filtq
        else
          (idx, term) = fq.split(":")
          term.sub!(/^\"/,'').sub!(/\"$/,'')
          bool.add_query(Ferret::Search::TermQuery.new(idx.to_sym, term), :must)
        end
      end
      unless bool.to_s.empty?
        @filter = Ferret::Search::QueryFilter.new(bool)
      end
    end
  end
  
  def init_parser
    @parser = Ferret::QueryParser.new(:fields=>CheapSkate.index.reader.tokenized_fields)
    @strict_parser = Ferret::QueryParser.new(:fields=>CheapSkate.index.reader.tokenized_fields, :validate_fields=>true, :handle_parse_errors=>false)
  end
end
