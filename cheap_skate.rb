module CheapSkate
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
  require 'lib/index'
  require 'lib/application'  
  require 'faster_csv'
end