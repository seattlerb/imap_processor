require 'imap_processor'

##
# Archives old mail on IMAP server by moving it to dated mailboxen.

class IMAPProcessor::Archive < IMAPProcessor
  attr_reader :list, :move

  def self.process_args(args)
    required_options = {
      :List => true,
      :Move => false,
    }

    super __FILE__, args, required_options do |opts, options|
      opts.banner << <<-EOF
imap_archive archives old mail on IMAP server by moving it to dated mailboxen.
      EOF

      opts.on("--[no-]list", "Display messages (on by default)") do |list|
        options[:List] = list
      end

      opts.on("--[no-]move", "Move the messages (off by default)") do |move|
        options[:Move] = move
      end
    end
  end

  def initialize(options)
    super

    @list = options[:List]
    @move = options[:Move]

    connection = connect

    @imap = connection.imap
  end

  def the_first
    t = Time.now
    the_first = Time.local(t.year, t.month, 1)
  end

  def last_month
    t = the_first - 1
    Time.local(t.year, t.month, 1).strftime("%Y-%m")
  end

  ##
  # Makes a SEARCH argument set from +keywords+

  def make_search
    %W[SENTBEFORE #{the_first.imapdate}]
  end

  def run
    @boxes.each do |mailbox|
      destination = "#{mailbox}.#{last_month}"
      create_mailbox destination

      log "SELECT #{mailbox}"
      response = imap.select mailbox

      search = make_search

      log "SEARCH #{search.join ' '}"
      uids = imap.search search

      next if uids.empty?

      puts "#{uids.length} messages in #{mailbox}#{list ? ':' : ''}"

      show_messages uids

      move_messages uids, destination if move
    end
  end

end

