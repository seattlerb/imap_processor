# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugin :seattlerb

Hoe.spec 'imap_processor' do |ip|
  ip.rubyforge_name = 'seattlerb'
  ip.developer 'Eric Hodel', 'drbrain@segment7.net'
end

task :irb do
  sh "irb -Ilib -rimap_processor"
end

# vim: syntax=Ruby
