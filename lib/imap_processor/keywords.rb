require 'imap_processor'

##
# Lists keywords present on a server

class IMAPProcessor::Keywords < IMAPProcessor

  def self.process_args(args)
    required_options = {
      :List => true
    }

    super __FILE__, args, required_options do |opts, options|
      opts.banner << <<-EOF
imap_keywords lists keywords on an IMAP server and allows you to delete
previously set keywords.
      EOF

#      opts.on(      "--add",
#              "Add keyword(s) to all messages") do |add|
#        options[:Add] = add
#      end

      opts.on(      "--delete",
              "Delete keyword(s) from all messages") do |delete|
        options[:Delete] = delete
      end

      opts.on(      "--keywords=KEYWORDS", Array,
              "Select messages with keyword(s),",
              "which will be ANDed") do |keywords|
        options[:Keywords] = keywords
      end

      opts.on(      "--[no-]list",
              "Display messages") do |list|
        options[:List] = list
      end

      opts.on(      "--not",
              "Select messages without --keywords") do
        options[:Not] = true
      end
    end
  end

  def initialize(options)
    super

    @add      = options[:Add]
    @delete   = options[:Delete]
    @keywords = options[:Keywords]
    @not      = options[:Not] ? 'NOT' : nil
    @list     = options[:List]

    if @add and @delete then
      raise OptionParser::InvalidOption, "--add and --delete are exclusive"
    elsif @keywords.nil? and (@add or @delete) then
      raise OptionParser::InvalidOption,
            "--add and --delete require --keywords"
    end

    connection = connect options[:Host], options[:Port], options[:SSL],
                         options[:Username], options[:Password], options[:Auth]

    @imap = connection.imap
  end

  ##
  # Turns +flags+ into a format usable by the IMAP server

  def flags_to_literal(flags)
    flags.flatten.map do |flag|
      case flag
      when Symbol then "\\#{flag}"
      else flag
      end
    end
  end

  ##
  # Makes a SEARCH argument set from +keywords+

  def make_search(keywords)
    if keywords then
      keywords.map do |kw|
        case kw
        when '\Answered', '\Deleted', '\Draft', '\Flagged',
             '\Recent', '\Seen' then
          [@not, kw[1..-1].upcase]
        else
          [@not, 'KEYWORD', kw]
        end
      end.flatten.compact
    else
      %w[ALL]
    end
  end

  def run
    @boxes.each do |mailbox|
      response = @imap.select mailbox
      log "Selected mailbox #{mailbox}"
      puts "Previously set flags:"
      puts flags_to_literal(@imap.responses['FLAGS']).join(' ')
      puts

      puts "Permanent flags:"
      puts flags_to_literal(@imap.responses['PERMANENTFLAGS']).join(' ')
      puts

      search = make_search @keywords

      log "SEARCH #{search.join ' '}"
      uids = @imap.search search

      if uids.empty? then
        puts "No messages"
        next
      else
        puts "#{uids.length} messages in #{mailbox}#{@list ? ':' : ''}"
      end

      @imap.store uids, '-FLAGS.SILENT', @keywords if @delete

      show_messages uids
    end
  end

  ##
  # Displays messages in +uids+ and their keywords

  def show_messages(uids)
    return unless @list

    responses = @imap.fetch uids, [
      Net::IMAP::RawData.new('BODY.PEEK[HEADER.FIELDS (SUBJECT MESSAGE-ID)]'),
      'FLAGS'
    ]

    responses.each do |res|
      header = res.attr['BODY[HEADER.FIELDS (SUBJECT MESSAGE-ID)]']

      puts header.chomp

      flags = res.attr['FLAGS'].map { |flag| flag.inspect }.join ', '

      puts "Flags: #{flags}"
      puts
    end
  end

end

