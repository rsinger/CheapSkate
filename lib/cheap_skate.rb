module CheapSkate
  $KCODE = 'u' 
  #stdlib dependencies 
  require "rubygems"
  require 'jcode'  
  require 'yaml'  
  require 'cgi'  
  
  #gem dependencies
  require 'faster_csv'
  require "uuid"
  require 'ferret'
  require 'json'
  require 'hpricot'
  require 'sinatra'

  #project files
  require File.dirname(__FILE__)+'/cheap_skate/models'
  require File.dirname(__FILE__)+'/cheap_skate/schema'
  require File.dirname(__FILE__)+'/cheap_skate/index'
  require File.dirname(__FILE__)+'/cheap_skate/application'  

end