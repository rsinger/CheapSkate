class Document < Hash

  attr_accessor :document_id
  
  def initialize(doc_id=UUID.generate)
    @document_id = doc_id
  end
  
  def save
    get_document_id
    self.delete_fields
    INDEX << self.to_document
    DocumentField.add_fields(self)
  end
  
  def get_document_id
    unless self.document_id
      self.document_id = UUID.generate
    end
    self.document_id
  end
  
  def to_document(stringify_keys=false)
    id_field = :id
    id_field = "id" if stringify_keys
    document = {id_field=>@document_id}
    self.each_pair do |key, val|
      next unless key
      if stringify_keys
        document[key.to_s] = val
      else
        document[key.to_sym] = val
      end
    end
    document
  end
  
  def delete(clear=true)
    INDEX.delete(self.document_id)
    delete_fields
    self.clear if clear
  end
  
  def delete_fields
    flds = DocumentField.all(:doc_id=>self.document_id)
    flds.destroy! unless flds.empty?
  end
  
  def self.delete(ids)
    [*ids].each do |id|
      INDEX.delete(id)     
    end
    flds = DocumentField.all(:doc_id=>ids)
    flds.destroy!
  end
    
  def add_field(key, value)
    if value.is_a?(Array)
      value.each do |v|
        add_field(key, v)
      end
    else      
      if self[key.to_sym]
        self[key.to_sym] = [*self[key.to_sym]]
        self[key.to_sym] << value
      else
        self[key.to_sym] = value
      end
    end
  end
  
  def self.search(query, opts={})
    results = ResultSet.new
    results.offset = opts[:offset]
    results.limit = opts[:limit]
    results.query = query
    results.total = INDEX.search_each(query, opts) do |id, score|
      doc = INDEX[id]
      
      field_types = {}
      DocumentField.all(:doc_id=>INDEX[id]).each do |fld|
        field_types[fld.field.to_sym] = fld.datatype
      end
      results << typed_document(doc, field_types)
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
  
  def self.search(query, opts={})
    results = self.new
    results.total = INDEX.search_each(query, opts) do |id, score|
      results << Document.first(:doc_id=>INDEX[id])
    end
    results.query = query
    results.offset = opts[:offset]||0
    results.limit = opts[:limit]||10
    results    
  end
  def to_hash()
    response = {"responseHeader"=>{"status"=>0, "QTime"=>self.query_time, "params"=>{"q"=>self.query, "version"=>"2.2", "rows"=>self.limit}}}
    response["response"] = {"numFound"=>self.total, "start"=>self.offset, "docs"=>[]}
    if self.docs
      self.docs.each do |doc|
        response["response"]["docs"] << doc.to_document(true)
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
    else
      response.query = params['q'].first
    end
    #response.query = (params["facet.query"]||params["q"]).first
    ids = []
    response.total = INDEX.search_each(response.query, :limit=>:all) do |id, score|
      break if score < CONFIG[:facet_score_threshold]
      ids << INDEX[id][:id]
    end
    if params['facet.limit'] && !params['facet.limit'].empty?
      response.limit = params['facet.limit'].first
    else
      response.limit = 10
    end
    if params['facet.offset'] && !params['facet.offset'].empty?
      response.offset = params['facet.offset']
    else
      response.offset = 0
    end
    
    
    params["facet.field"].each do | field |
      response.fields << field
      response.facets[field] = []
      facets = repository(:default).adapter.select("SELECT DISTINCT value, count(value) as facet_count FROM document_fields WHERE doc_id IN ('#{ids.join("', '")}') AND field = '#{field}' GROUP BY value ORDER BY facet_count LIMIT #{response.offset},#{response.limit}")
      facets.each do | facet |        
        response.facets[field] << [facet.value, facet.facet_count]
      end
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
            document.document_id = value
          else
            document.add_field(field, value)
          end
        end
      end      
      document.save
    end
  end
  
  def commit
    INDEX.flush
  end
  
  def delete
    ids = []
    (@doc/"/delete/id").each do |del|
      ids << del.inner_html
    end
    (@doc/"/delete/query").each do |del|
      INDEX.search_each(del.attributes['q'], :limit=>:all) do |id,score|
        ids << id
      end      
    end
    unless ids.empty?
      Document.delete(ids)
    end
  end
  
  def optimize
    INDEX.optimize
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

class DocumentField
  include DataMapper::Resource
  property :id, Serial
  property :doc_id, String, :index=>true
  property :field, String, :index=>true
  property :value, String, :index=>true, :length=>255 
  property :datatype, String
  
  def self.add_fields(doc)
    collection = self.all(:doc_id => doc.document_id)
    doc.each_pair do |key, val|
      [*val].each do |v|
        begin
          collection.new(:doc_id=>doc.document_id, :field=>key.to_s, :value=>v.each_char[0,255].join, :datatype=>v.class.name)
        rescue
          puts "Error adding :field=>#{key}, :value=>#{v.to_s[0,255]} for document: #{doc.document_id}"
        end
      end      
    end
    collection.save!
  end
  
  def self.add_field(doc_id, field, value)
    fld = self.new(:doc_id=>doc_id, :field=>field.to_s, :value=>value.each_char[0,255].join, :datatype=>value.class.name)
    fld.save
  end
end

class CSVLoader
  
end
