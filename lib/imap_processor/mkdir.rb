require 'imap_processor'

##
# Creates folders in IMAP.

class IMAPProcessor::Mkdir < IMAPProcessor
  attr_reader :sep

  def self.process_args(args)
    super __FILE__, args
  end

  def initialize(options)
    super

    @imap = connect.imap
  end

  def run
    ARGV.each do |mailbox|
      create_mailbox mailbox
    end
  end
end

