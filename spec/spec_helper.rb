require 'rubygems'
require 'bundler/setup'
require 'pry'
require 'fakeweb'
require File.dirname(__FILE__) + '/fakeweb_helper'

$:.unshift(File.dirname(__FILE__) + '/../lib/')
require 'medusa'

Dir["./spec/support/**/*.rb"].sort.each {|f| require f}

SPEC_DOMAIN = 'http://www.example.com/'
