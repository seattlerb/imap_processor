require 'imap_processor'
require "time"

##
# Archives old mail on IMAP server by moving it to dated mailboxen.

class IMAPProcessor::Archive < IMAPProcessor
  attr_reader :list, :move, :sep, :merge

  def self.process_args(args)
    required_options = {
      :List => true,
      :Move => false,
      :Merge => false,
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

      opts.on("--[no-]merge", "Merge multiple months into current month (off by default)") do |move|
        options[:Merge] = move
      end

      opts.on("-s", "--sep SEPARATOR",
              "Mailbox date separator character",
              "Default: Read from ~/.#{@@opts_file_name}",
              "Options file name: :Sep") do |sep|
        options[:Sep] = sep
      end
    end
  end

  def initialize(options)
    super

    @list = options[:List]
    @move = options[:Move]
    @sep  = options[:Sep] || '.'
    @merge = options[:Merge]

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
      log "SELECT #{mailbox}"
      response = imap.select mailbox

      uids_by_date = self.uids_by_date

      next if uids_by_date.empty?

      if merge then
        latest = uids_by_date.keys.max
        uids_by_date = {
          latest => uids_by_date.values.flatten(1)
        }
      end

      uids_by_date.sort.each do |date, uids|
        next if uids.empty?
        destination = "#{mailbox}#{sep}%4d-%02d" % date
        puts "#{destination}:"
        puts
        show_messages uids
        move_messages uids, destination, false if move
      end

      log "EXPUNGE"
      imap.expunge
    end
  end

  def uids_by_date
    search = make_search
    log "SEARCH #{search.join ' '}"
    uids = imap.search search

    return {} if uids.empty?

    payload = imap.fetch(uids, 'BODY.PEEK[HEADER.FIELDS (DATE)]')

    mail = Hash[uids.zip(payload).map { |uid, m|
      date = m.attr["BODY[HEADER.FIELDS (DATE)]"].strip.split(/:\s*/, 2).last
      [uid, Time.parse(date)]
    }]

    mail.keys.group_by { |uid|
      date = mail[uid]
      [date.year, date.month]
    }
  end
end
