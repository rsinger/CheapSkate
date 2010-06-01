require 'rexml/document'
require 'yaml'
module CheapSkate
  class Schema
    include CheapSkate
    attr_reader :name, :fields, :config, :field_types, :id_field, :copy_fields, :dynamic_fields, :default_field, :default_operator
    def self.xml_to_yaml(xml)
      doc = REXML::Document.new xml
      y = {"schema"=>{"types"=>{}, "fields"=>{}}}
      y["schema"]["name"] = doc.root.attributes["name"]
      y["schema"]["version"] = doc.root.attributes["version"]
      doc.each_element("/schema/fields/field") do |field|
        f = {}
        field.attributes.each do |a,v|
          next if a == "name"
          f[a] = case v
          when "true" then true
          when "false" then false
          else v
          end
        end
        y["schema"]["fields"][field.attributes['name']] = f
      end
      doc.each_element("/schema/fields/dynamicField") do |dyn_field|
        f = {}
        dyn_field.attributes.each do |a,v|
          next if a == "name"
          f[a] = case v
          when "true" then true
          when "false" then false
          else v
          end
        end
        y["schema"]["dynamic_fields"] ||= {}
        y["schema"]["dynamic_fields"][dyn_field.attributes['name']] = f
      end    
      doc.each_element("/schema/types/fieldType") do |type|
        t = {}
        t[:type] = case type.attributes['class']
        when "solr.StrField" then :string
        when "solr.TextField" then :text
        when "solr.IntField" then :int
        when "solr.FloatField" then :float
        when "solr.BoolField" then :bool
        when "solr.DateField" then :date
        end
        if type.attributes['omitNorms'] &&  type.attributes['omitNorms'] == "true"
          t[:index] = :omit_norms
        end
        unless t[:type] == :text
          if t[:index] == :omit_norms
            t[:index] = :untokenized_omit_norms
          else
            t[:index] = :untokenized
          end
        end
        y["schema"]["types"][type.attributes['name']] = t
      end
      doc.each_element("/schema/types/fieldtype") do |type|
        t = {}
        t[:type] = case type.attributes['class']
        when "solr.StrField" then :string
        when "solr.TextField" then :text
        when "solr.IntField" then :int
        when "solr.FloatField" then :float
        when "solr.BoolField" then :bool
        when "solr.DateField" then :date
        end
        if type.attributes['omitNorms'] &&  type.attributes['omitNorms'] == "true"
          t[:index] = :omit_norms
        end
        unless t[:type] == :text
          if t[:index] == :omit_norms
            t[:index] = :untokenized_omit_norms
          else
            t[:index] = :untokenized
          end
        end
        y["schema"]["types"][type.attributes['name']] = t
      end  
      if dflt = doc.elements['/schema/defaultSearchField']
        y["schema"]["defaultSearchField"] = dflt.get_text.value if dflt.has_text?
      end
      if uniq_key = doc.elements['/schema/uniqueKey']
        y["schema"]["uniqueKey"] = uniq_key.get_text.value if uniq_key.has_text?
      end    
      copy_fields = []
      doc.each_element("/schema/copyField") do |copy|
        copy_fields << {copy.attributes['source']=>copy.attributes['dest']}
      end
      unless copy_fields.empty?
        y["schema"]["copyFields"] = copy_fields
      end
      y.to_yaml
    end
  
    def self.new_from_config(config_hash)
      schema = self.new
      schema.load_from_conf(config_hash)
      schema
    end
  
    def initialize
      @copy_fields = {}
    end
  
    def load_from_conf(conf)
      @fields ={}
      @field_types ={}
      @name = conf['schema']['name']
      conf['schema']['fields'].keys.each do |field|
        @fields[field.to_sym] = {}
        fld = conf['schema']['fields'][field]
        @fields[field.to_sym][:field_type] = fld['type'].to_sym
        if fld['indexed'] == false
          @fields[field.to_sym][:index] = :no
        end
        if fld['stored'] == false
          @fields[field.to_sym][:store] = :no
        end  
        @fields[field.to_sym][:multi_valued] = fld['multiValued']||false
      end
      if conf['schema']['dynamic_fields']
        conf['schema']['dynamic_fields'].keys.each do |field|
          @dynamic_fields ||= {}
          @dynamic_fields[field.to_sym] = {}
          fld = conf['schema']['dynamic_fields'][field]
          @dynamic_fields[field.to_sym][:field_type] = fld['type'].to_sym
          if fld['indexed'] == false
            @dynamic_fields[field.to_sym][:index] = :no
          end
          if fld['stored'] == false
            @dynamic_fields[field.to_sym][:store] = :no
          end  
          @dynamic_fields[field.to_sym][:multi_valued] = fld['multiValued']||false
        end  
      end  
      conf['schema']['types'].keys.each do |type|
        @field_types[type.to_sym] = conf['schema']['types'][type]
      end
      conf['schema']['copyFields'].each do |copy|
        copy.each_pair do | orig, dest|
          @copy_fields[orig.to_sym] ||= []
          @copy_fields[orig.to_sym] << dest.to_sym
        end
      end
      @id_field = (conf['schema']['uniqueKey'] || "id").to_sym
      @default_field = (conf['schema']['defaultSearchField']||"*").to_sym
      @default_operator = (conf['schema']['defaultOperator']||"OR")   
    end
  
    def typed_document(lazy_doc)
      doc = {}
      lazy_doc.fields.each do |field|
        [*lazy_doc[field]].each do |fld|
          if doc[field]
            doc[field] = [*doc[field]]
            doc[field] << type_field(field, fld)
          elsif multi_valued?(field)
            doc[field] = [type_field(field, fld)]
          else
            doc[field] = type_field(field, fld)
          end
        end
      end
      doc    
    end
  
    def multi_valued?(field)
      if @fields[field]
        return @fields[field][:multi_valued]
      else
        dyn_field = nil
        @dynamic_fields.keys.each do |dyn|
          if dyn =~ /^\*/
            r = Regexp.new(dyn.sub(/^\*/,".*"))
          elsif dyn =~ /\*$/
            r = Regexp.new(dyn.sub(/\*$/,".*"))
          end
          if field =~ dyn
            dyn_field = dyn
            break
          end        
        end
        return dyn_field[:multi_valued] if dyn_field        
      end
      false
    end
  
    def type_field(field_name, value)
      return value.to_s unless @fields[field_name]
      val = case @field_types[@fields[field_name][:field_type]][:type]
      when :string then value.to_s
      when :text then value.to_s
      when :int then value.to_i
      when :float then value.to_f
      when :date then Date.parse(value)
      when :bool
        if value == "true"
          true
        else
          false
        end
      else
        val.to_s
      end
      val
    end
  
    def field_names
      return @fields.keys
    end
  
    def field_to_field_info(field_name)
      opts = {}
      if @fields[field_name][:index] == :no
        opts[:index] = :no
        opts[:term_vector] = :no
      elsif @field_types[@fields[field_name][:field_type]][:index]
        opts[:index] = @field_types[@fields[field_name][:field_type]][:index]
      end
      if @fields[field_name][:stored] == :no
        opts[:store] = :no
      end
      Ferret::Index::FieldInfo.new(field_name, opts)
    end
  
  end
end