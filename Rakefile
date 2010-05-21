begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "cheap_skate"
    gemspec.summary = "A very simple Solr emulator in Ruby"
    gemspec.description = "A Solr-like interface for situations where running a Java application server is not an option (such as shared web hosting)."
    gemspec.email = "rossfsinger@gmail.com"
    gemspec.homepage = "http://github.com/rsinger/CheapSkate"
    gemspec.authors = ["Ross Singer"]
    gemspec.files = FileList['lib/**/*.rb','conf/*-dist','config.ru-dist', 'cheap_skate.rb']
    gemspec.add_dependency 'fastercsv'
    gemspec.add_dependency "uuid"
    gemspec.add_dependency 'ferret'
    gemspec.add_dependency 'json'
    gemspec.add_dependency 'hpricot'
    gemspec.add_dependency 'sinatra'    
  end
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end
