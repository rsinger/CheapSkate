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
      reader.field_infos.add_field(field, opts)
    end
        
    def search(query, opts={})
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

      results.total = self.search_each(query.query, opts) do |id, score|
        results << @schema.typed_document(self[id])
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
      puts query.facet_fields.inspect
      query.facet_fields.keys.each do |field|
        field_terms = reader.terms(field)
        next unless field_terms
        field_terms.each do |term, count|
          query.facet_fields[field][term] = count
        end
      end
    end      
    

    def parse_standard_query(params)
      or_and = case 
      when params["q.op"] then [*params["q.op"]].first
      else schema.default_operator
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
      if params['fq']
        query.filter = parse_filtered_query(params)
      end
      query
    end
    
    def parse_filtered_query(params)
      or_and = case 
      when params["q.op"] then [*params["q.op"]].first
      else schema.default_operator
      end

      dflt_field = case
      when params["df"] then [*params["df"]].first
      else schema.default_field
      end

      strict_parser = Ferret::QueryParser.new(:default_field=>dflt_field, :fields=>reader.tokenized_fields, :validate_fields=>true, :or_default=>(or_and=="OR"), :handle_parse_errors=>false)
      bool = Ferret::Search::BooleanQuery.new
      [*params['fq']].each do |fq|
        if (filtq = strict_parser.parse(fq) && !filtq.to_s.empty?)
          bool.add_query(filtq, :must)
        else
          (idx, term) = fq.split(":")
          term.sub!(/^\"/,'').sub!(/\"$/,'')
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

    end    
  end
end