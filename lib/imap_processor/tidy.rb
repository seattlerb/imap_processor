require "imap_processor"
require "net/imap/date"

##
# Whereas Archive moves all mail before this month into a dated mailbox, and
# whereas Cleanse deletes all read unflagged mail over N days old,
# Tidy moves all read unflagged mail into a dated mailbox.
#
# It's somewhere in-between Archive and Cleanse in that it is used for
# mail you want to keep, but also keep out of the way of your active
# inbox.

class IMAPProcessor::Tidy < IMAPProcessor

  ##
  # Whether to move the mail or just display. default:false

  attr_accessor :move

  def self.process_args args # :nodoc:
    required_options = {
      :move => false,
    }

    super __FILE__, args, required_options do |opts, options|
      opts.banner << <<~EOF
        imap_tidy moves older messages from your mailboxen into dated mailboxen.
      EOF

      opts.on "--days=N", Integer, "Override age to move messages" do |n|
        options[:age] = n
      end

      opts.on "--[no-]move", "Move the messages (off by default)" do |move|
        options[:move] = move
      end
    end
  end

  def initialize options # :nodoc:
    super

    log "Tidy: #{options[:Host]}"

    self.move = options[:move]

    connection = connect

    @imap = connection.imap
  end

  ##
  # Select a mailbox
  # TODO: push up

  def select mailbox
    log "SELECT #{mailbox}"
    imap.select mailbox
  end

  ##
  # Search a selected mailbox with +args+
  # TODO: push up

  def search args
    log "SEARCH #{args.join " "}"
    imap.search args
  end

  def uids_to_dates uids
    imap
      .fetch(uids, "INTERNALDATE")
      .to_h { |fd| [fd.seqno, Time.imapdate(fd.attr["INTERNALDATE"]).yyyy_mm] }
  end

  def run
    @boxes.each do |mailbox, days_old|
      select mailbox

      before_date = Time.now - 86_400 * (options[:age] || days_old)
      uids        = search %W[SEEN UNFLAGGED BEFORE #{before_date.imapdate}]

      next if uids.empty?

      log "FOUND %p" % [uids]

      uids_to_dates(uids)                 # id => "YYYY-MM"
        .multi_invert                     # "YYYY-MM" => [id,...]
        .sort
        .each do |date, uids|
          destination = "%s-%s" % [mailbox, date]
          show_messages uids
          move_messages uids, destination, false if move
        end

      log "EXPUNGE"
      imap.expunge if move unless noop?
    end
  end
end

class Hash
  def multi_invert
    keys.group_by { |k| self[k] }.to_h
  end
end
