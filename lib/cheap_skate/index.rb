module CheapSkate
  class Index < Ferret::Index::Index
    attr_accessor :schema
    def initialize(opts={}, schema=CheapSkate::Schema.new)
      super(opts)
      @schema = schema
    end
    
    def set_fields_from_schema
      index_schema_changed = false
      schema.field_names.each do |fld|
        f = schema.field_to_field_info(fld)
        if !field_infos[f.name]
          self.writer.field_infos << f
          self.reader.field_infos << f
          index_schema_changed = true
        end
      end
      puts "Schema has changed" if index_schema_changed
        
    end
    
    def set_dynamic_field(field)
      return if field_infos[field]

      return if schema.fields[field]

      dyn_field = nil
      schema.dynamic_fields.keys.each do |dyn|
        if dyn =~ /^\*/
          r = Regexp.new(dyn.sub(/^\*/,".*"))
        elsif dyn =~ /\*$/
          r = Regexp.new(dyn.sub(/\*$/,".*"))
        end
        unless (field.to_s =~ r).nil?
          dyn_field = dyn
          break
        else
          puts "Unable to match #{field.to_s} against a dynamic field pattern"
        end
      end
      return unless dyn_field
      opts = {}
      if schema.dynamic_fields[dyn_field][:index] == :no
        opts[:index] = :no
        opts[:term_vector] = :no
      elsif schema.field_types[schema.dynamic_fields[dyn_field][:field_type]][:index]
        opts[:index] = schema.field_types[schema.dynamic_fields[dyn_field][:field_type]][:index]
      end
      if schema.dynamic_fields[dyn_field][:stored] == :no
        opts[:store] = :no
      end    
      puts "Adding dynamic field: #{field}"
      writer.field_infos.add_field(field, opts)
    end
        
    def do_search(query, opts={})
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
      
      if query.filter_proc
        if query.query.is_a?(Ferret::Search::MatchAllQuery) && query.filter.nil?
          get_facets_from_index_terms(query)
        else
          opts[:filter_proc] = query.filter_proc
        end
      end
      searcher = Ferret::Search::Searcher.new(self.reader)
      hits = searcher.search(query.query, opts)
      results.total = hits.total_hits
      results.max_score = hits.max_score
      hits.hits.each do |hit|
       doc = @schema.typed_document(self[hit.doc])
       doc[:score] = hit.score
       results << doc      
      end
      if query.respond_to?(:facet_fields)
        facets = {}
        query.facet_fields.each do | facet, values |
          facets[facet] = values.sort{|a,b| b[1]<=>a[1]}[query.facet_offset, query.facet_limit]
        end          
        query.facet_fields = facets
        if query.facet_queries
          query.facet_queries.each do |fq|        
            fq[:results] = search_each(fq.query, :filter=>fq.filter, :limit=>1) {|id,score|}
          end
        end
        results.extend(Facet)
        results.add_facets_to_results(query)
      end
      results
    end
    
    def get_facets_from_index_terms(query)
      query.facet_fields.keys.each do |field|
        field_terms = reader.terms(field)
        next unless field_terms
        field_terms.each do |term, count|
          query.facet_fields[field][term] = count
        end
      end
    end      
    

    def parse_standard_query(params)
      if params["q.op"] && !params["q.op"].empty?
        or_and = [*params["q.op"]].first
      else 
        or_and = schema.default_operator
      end
      dflt_field = case
      when params["df"] then [*params["df"]].first
      else schema.default_field
      end
      parser = Ferret::QueryParser.new(:default_field=>dflt_field, :fields=>reader.tokenized_fields, :or_default=>(or_and=="OR"))

      query = CheapSkate::Query.new
      q = case params["q"].class.name
      when "Array" then params["q"].first
      when "String" then params["q"]
      else nil
      end
      if q && !q.empty? && q != "*:*"
        query.query = parser.parse(q)
      else
        query.query = Ferret::Search::MatchAllQuery.new
      end
      if params['fq'] && !params['fq'].empty?
        query.filter = parse_filtered_query(params)
      end
      query
    end
    
    def parse_filtered_query(params)
      if params["q.op"] && !params["q.op"].empty?
        or_and = [*params["q.op"]].first
      else 
        or_and = schema.default_operator
      end

      dflt_field = case
      when params["df"] then [*params["df"]].first
      else schema.default_field
      end

      strict_parser = Ferret::QueryParser.new(:default_field=>dflt_field, :fields=>reader.tokenized_fields, :validate_fields=>true, :or_default=>(or_and=="OR"), :handle_parse_errors=>false)
      bool = Ferret::Search::BooleanQuery.new
      [*params['fq']].each do |fq|
        next if fq.nil? or fq.empty?
        if (filtq = strict_parser.parse(fq) && !filtq.to_s.empty?)
          bool.add_query(filtq, :must)
        else
          (idx, term) = fq.split(":")
          term = term.sub(/^\"/,'').sub(/\"$/,'')
          bool.add_query(Ferret::Search::TermQuery.new(idx.to_sym, term), :must)
        end
      end
      unless bool.to_s.empty?
        return Ferret::Search::QueryFilter.new(bool)
      end
      nil
    end
    

    def parse_dismax_query(params)
      parse_standard_query(params)
    end

    def parse_morelikethis_query(params)
      q = case params["q"].class.name
      when "Array" then params["q"].first
      when "String" then params["q"]
      else "*:*"
      end
      opts = {}
      opts[:limit] = 1
      if params['mlt.match.offset']
        opts[:offset] = [*params['mlt.match.offset']].first.to_i
      end
      mlt = nil
      self.search_each(q, opts) do |doc, score|
        mlt = self[doc].load
      end
      bool = Ferret::Search::BooleanQuery.new
        unless params['mlt.match.include'] && [*params['mlt.match.include']].first == "true"
          b = Ferret::Search::BooleanQuery.new
          bool.add_query(Ferret::Search::TermQuery.new(:id, mlt[:id]), :must_not)
        end      
      mlt.each_pair do |key, val|

        if val.is_a?(Array)
          val.each do | v |
            b = Ferret::Search::BooleanQuery.new
            b.add_query(Ferret::Search::TermQuery.new(key, v))
            bool << b
          end
        else
          b = Ferret::Search::BooleanQuery.new
          b.add_query(Ferret::Search::TermQuery.new(key, val))
          bool << b
        end
      end
      query = CheapSkate::Query.new
      
      # No idea why this is necessary, but Ferret will ignore our boolean NOT otherwise
      p = Ferret::QueryParser.new      
      query.query = p.parse(bool.to_s)

      return query
    end
    
    def create_document(id=UUID.generate, boost=1.0)
      d = CheapSkate::Document.new(id, boost)
      d.index = self
      d
    end
    
    def luke(params)
      response = LukeResponse.new
      response.num_docs = reader.num_docs
      response.max_doc = reader.max_doc
      response.version = reader.version
      response.optimized = true # Hard code this -- not sure there's any way to get this from Ferret
      response.current = reader.version == writer.version
      response.has_deletions = reader.has_deletions?
      response.directory = options[:path]
      response.last_modified = Time.now.xmlschema # I don't see this in Ferret, either
      reader.field_infos.each do | field |
        schema_field = schema.fields[field.name]
        if schema_field
          luke_field = {:type=>schema_field[:type]}
          multivalued = schema.multi_valued?(field.name)
        else
          luke_field = {:type=>"text"}
          multivalued = true
        end
        schema_string = ""
        schema_string << case field.indexed?
        when true then "I"
        else "-"
        end
        schema_string << case field.tokenized?
        when true then "T"
        else "-"
        end
        
        schema_string << case field.stored?
        when true then "S"
        else "-"
        end
        
        schema_string << case multivalued
        when true then "M"
        else "-"
        end
        
        schema_string << case field.store_term_vector?
        when true then "V"
        else "-"
        end
        
        schema_string << case field.store_offsets?
        when true then "o"
        else "-"
        end        
        
        schema_string << case field.store_positions?
        when true then "p"
        else "-"
        end        
        
        schema_string << case field.omit_norms?
        when true then "O"
        else "-"
        end  
        schema_string << "--"
        
        schema_string << case field.compressed?
        when true then "C"
        else "-"
        end   
        
        schema_string << "--"     
        response.fields[field.name] = {:schema=>schema_string}
        #terms = {}
        #reader.terms(field.name).each do |term, count|
        #  terms[term] = count
        #end
        
      end
      response
    end
  end
end