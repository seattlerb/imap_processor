require 'imap_processor'
require 'net/imap/idle'

##
# Example class that supports IDLE on a mailbox and lists messages added or
# expunged.

class IMAPProcessor::IDLE < IMAPProcessor

  def self.process_args(args)
    super __FILE__, args do |opts, options|
      opts.banner << <<-EOF
imap_idle lists messages added or expunged from a mailbox
      EOF
    end
  end

  def initialize(options)
    super

    raise IMAPProcessor::Error, 'only one mailbox is supported' if
      @boxes.length > 1
  end

  def run
    mailbox = @boxes.first

    connect do |connection|
      raise IMAPProcessor::Error, 'IDLE not supported on this server' unless
        connection.idle?

      imap = connection.imap

      imap.select mailbox
      exists = imap.responses['EXISTS'].first

      log "Starting IDLE"

      imap.idle do |response|
        next unless Net::IMAP::UntaggedResponse === response

        case response.name
        when 'EXPUNGE' then
          puts "Expunged message #{response.data}"
        when 'EXISTS' then
          latest_uid = response.data
          new = latest_uid - exists
          puts "#{new} messages added"

          show_messages_in mailbox, ((exists + 1)..latest_uid)

          exists = response.data
        when 'RECENT' then
          puts "#{response.data} recent messages"
        when 'OK' then # ending IDLE
        else
          log "Unhandled untagged response: #{response.name}"
        end
      end
    end
  end

  def show_messages_in(mailbox, uids)
    connect do |connection|
      imap = connection.imap

      imap.select mailbox

      show_messages uids
    end
  end

end

