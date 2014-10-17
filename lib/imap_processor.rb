require 'rubygems'
require 'optparse'
require 'net/imap'
require 'net/imap/date'
require 'imap_sasl_plain'
require 'yaml'

##
# IMAPProcessor is a client for processing messages on an IMAP server.
#
# Subclasses need to provide:
#
# * A process_args class method that adds any extra options to the default
#   IMAPProcessor options.
# * An initialize method that connects to an IMAP server and sets the @imap
#   instance variable
# * A run method that uses the IMAP connection to process messages.
#
# Reference:
#
#     email: http://www.ietf.org/rfc/rfc0822.txt
#      imap: http://www.ietf.org/rfc/rfc3501.txt

class IMAPProcessor

  ##
  # The version of IMAPProcessor you are using

  VERSION = "1.6"

  ##
  # Base IMAPProcessor error class

  class Error < RuntimeError
  end

  ##
  # A Connection Struct that has +imap+ and +capability+ accessors

  class Connection < Struct.new :imap, :capability

    ##
    # Does this connection support the IDLE extension?

    def idle?
      capability.include? 'IDLE'
    end

    ##
    # Does this connection support the UIDPLUS extension?

    def uidplus?
      capability.include? 'UIDPLUS'
    end

  end

  ##
  # Net::IMAP connection, set this via #initialize

  attr_reader :imap

  ##
  # Options Hash from process_args

  attr_reader :options

  @@options = {}
  @@extra_options = []

  ##
  # Adds a --move option to the option parser which stores the destination
  # mailbox in the MoveTo option.  Call this from a subclass' process_args
  # method.

  def self.add_move
    @@options[:MoveTo] = nil

    @@extra_options << proc do |opts, options|
      opts.on(      "--move=MAILBOX",
              "Mailbox to move message to",
              "Default: #{options[:MoveTo].inspect}",
              "Options file name: :MoveTo") do |mailbox|
        options[:MoveTo] = mailbox
      end
    end
  end

  ##
  # Handles processing of +args+ loading defaults from a file in ~ based on
  # +processor_file+.  Extra option defaults can be specified by
  # +required_options+.  Yields an option parser instance to add new
  # OptionParser options to:
  #
  #   class MyProcessor < IMAPProcessor
  #     def self.process_args(args)
  #       required_options = {
  #         :MoveTo => [nil, "MoveTo not set"],
  #       }
  #
  #       super __FILE__, args, required_options do |opts, options|
  #         opts.banner << "Explain my_processor's executable"
  #
  #         opts.on(      "--move=MAILBOX",
  #                 "Mailbox to move message to",
  #                 "Default: #{options[:MoveTo].inspect}",
  #                 "Options file name: :MoveTo") do |mailbox|
  #           options[:MoveTo] = mailbox
  #         end
  #       end
  #     end
  #   end
  #
  # NOTE:  You can add a --move option using ::add_move

  def self.process_args(processor_file, args,
                        required_options = {}) # :yield: OptionParser
    @@opts_file_name = File.basename processor_file, '.rb'
    @@opts_file_name = "imap_#{@@opts_file_name}" unless
      @@opts_file_name =~ /^imap_/
    opts_file = File.expand_path "~/.#{@@opts_file_name}"

    if required_options then
      required_options.each do |option, (default, message)|
        raise ArgumentError,
              "required_options message is missing for #{option}" if
          default.nil? and message.nil?
      end
    end

    defaults = [{}]

    if File.exist? opts_file then
      unless File.stat(opts_file).mode & 077 == 0 then
        $stderr.puts "WARNING! #{opts_file} is group/other readable or writable!"
        $stderr.puts "WARNING! I'm not doing a thing until you fix it!"
        exit 1
      end

      defaults = YAML.load_file(opts_file)
      defaults = [defaults] unless Array === defaults
    end

    defaults.map { |default|
      options = default.merge @@options.dup

      options[:SSL]        = true unless options.key? :SSL
      options[:Username] ||= ENV['USER']
      options[:Root]     ||= nil
      options[:Verbose]  ||= false
      options[:Debug]    ||= false

      required_options.each do |k,(v,_)|
        options[k]       ||= v
      end

      op = OptionParser.new do |opts|
        opts.program_name = File.basename $0
        opts.banner = "Usage: #{opts.program_name} [options]\n\n"

        opts.separator ''
        opts.separator 'Connection options:'

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.on("-H", "--host HOST",
                "IMAP server host",
                "Default: #{options[:Host].inspect}",
                "Options file name: :Host") do |host|
          options[:Host] = host
        end

        opts.on("-P", "--port PORT",
                "IMAP server port",
                "Default: The correct port SSL/non-SSL mode",
                "Options file name: :Port") do |port|
          options[:Port] = port
        end

        opts.on("-s", "--[no-]ssl",
                "Use SSL for IMAP connection",
                "Default: #{options[:SSL].inspect}",
                "Options file name: :SSL") do |ssl|
          options[:SSL] = ssl
        end

        opts.on(      "--[no-]debug",
                "Display Net::IMAP debugging info",
                "Default: #{options[:Debug].inspect}",
                "Options file name: :Debug") do |debug|
          options[:Debug] = debug
        end

        opts.separator ''
        opts.separator 'Login options:'

        opts.on("-u", "--username USERNAME",
                "IMAP username",
                "Default: #{options[:Username].inspect}",
                "Options file name: :Username") do |username|
          options[:Username] = username
        end

        opts.on("-p", "--password PASSWORD",
                "IMAP password",
                "Default: Read from ~/.#{@@opts_file_name}",
                "Options file name: :Password") do |password|
          options[:Password] = password
        end

        authenticators = Net::IMAP.send :class_variable_get, :@@authenticators
        auth_types = authenticators.keys.sort.join ', '
        opts.on("-a", "--auth AUTH", auth_types,
                "IMAP authentication type override",
                "Authentication type will be auto-",
                "discovered",
                "Default: #{options[:Auth].inspect}",
                "Options file name: :Auth") do |auth|
          options[:Auth] = auth
        end

        opts.separator ''
        opts.separator "IMAP options:"

        opts.on("-r", "--root ROOT",
                "Root of mailbox hierarchy",
                "Default: #{options[:Root].inspect}",
                "Options file name: :Root") do |root|
          options[:Root] = root
        end

        opts.on("-b", "--boxes BOXES", Array,
                "Comma-separated list of mailbox names",
                "to search",
                "Default: #{options[:Boxes].inspect}",
                "Options file name: :Boxes") do |boxes|
          options[:Boxes] = boxes
        end

        opts.on("-v", "--[no-]verbose",
                "Be verbose",
                "Default: #{options[:Verbose].inspect}",
                "Options file name: :Verbose") do |verbose|
          options[:Verbose] = verbose
        end

        opts.on("-n", "--noop",
                "Perform no destructive operations",
                "Best used with the verbose option",
                "Default: #{options[:Noop].inspect}",
                "Options file name: Noop") do |noop|
          options[:Noop] = noop
        end

        opts.on("-q", "--quiet",
                "Be quiet") do
          options[:Verbose] = false
        end

        if block_given? then
          opts.separator ''
          opts.separator "#{self} options:"

          yield opts, options if block_given?
        end

        @@extra_options.each do |block|
          block.call opts, options
        end

        opts.separator ''

        opts.banner << <<-EOF

Options may also be set in the options file ~/.#{@@opts_file_name}

Example ~/.#{@@opts_file_name}:
\tHost=mail.example.com
\tPassword=my password

        EOF

      end # OptionParser.new do

      op.parse! args

      options[:Port] ||= options[:SSL] ? 993 : 143

      # HACK: removed :Boxes -- push down
      required_keys = [:Host, :Password] + required_options.keys
      if required_keys.any? { |k| options[k].nil? } then
        $stderr.puts op
        $stderr.puts
        $stderr.puts "Host name not set" if options[:Host].nil?
        $stderr.puts "Password not set"  if options[:Password].nil?
        $stderr.puts "Boxes not set"     if options[:Boxes].nil?
        required_options.each do |option_name, (_, missing_message)|
          $stderr.puts missing_message if options[option_name].nil?
        end
        exit 1
      end

      options
    } # defaults.map
  end

  ##
  # Sets up an IMAP processor's options then calls its \#run method.

  def self.run(args = ARGV, &block)
    client = nil
    multi_options = process_args args

    multi_options.each do |options|
      client = new(options, &block)
      client.run
    end
  rescue Interrupt
    exit
  rescue SystemExit
    raise
  rescue Exception => e
    $stderr.puts "Failed to finish with exception: #{e.class}:#{e.message}"
    $stderr.puts "\t#{e.backtrace.join "\n\t"}"

    exit 1
  ensure
    client.imap.logout if client and client.imap
  end

  ##
  # Handles the basic settings from +options+ including verbosity, mailboxes
  # to process, and Net::IMAP::debug

  def initialize(options)
    @options = options
    @verbose = options[:Verbose]
    @boxes = options[:Boxes]
    Net::IMAP.debug = options[:Debug]
  end

  ##
  # Extracts capability information for +imap+ from +res+ or by contacting the
  # server.

  def capability imap, res = nil
    return imap.capability unless res

    data = res.data

    if data.code and data.code.name == 'CAPABILITY' then
      data.code.data.split ' '
    else
      imap.capability
    end
  end

  ##
  # Connects to IMAP server +host+ at +port+ using ssl if +ssl+ is true then
  # authenticates with +username+ and +password+.  IMAPProcessor is only known
  # to work with PLAIN auth on SSL sockets.  IMAPProcessor does not support
  # LOGIN.
  #
  # Returns a Connection object.

  def connect(host = @options[:Host],
              port = @options[:Port],
              ssl = @options[:SSL],
              username = @options[:Username],
              password = @options[:Password],
              auth = @options[:Auth]) # :yields: Connection
    imap = Net::IMAP.new host, port, ssl, nil, false
    log "Connected to imap://#{host}:#{port}/"

    capabilities = capability imap, imap.greeting

    log "Capabilities: #{capabilities.join ', '}"

    auth_caps = capabilities.select { |c| c =~ /^AUTH/ }

    if auth.nil? then
      raise "Couldn't find a supported auth type" if auth_caps.empty?
      auth = auth_caps.first.sub(/AUTH=/, '')
    end

    # Net::IMAP supports using AUTHENTICATE with LOGIN, PLAIN, and
    # CRAM-MD5... if the server reports a different AUTH method, then we
    # should fall back to using LOGIN
    if %w( LOGIN PLAIN CRAM-MD5 XOAUTH2 ).include?( auth.upcase )
      auth = auth.upcase
      log "Trying #{auth} authentication"
      res = imap.authenticate auth, username, password
      log "Logged in as #{username} using AUTHENTICATE"
    else
      log "Trying to authenticate via LOGIN"
      res = imap.login username, password
      log "Logged in as #{username} using LOGIN"
    end

    # CAPABILITY may have changed
    capabilities = capability imap, res

    connection = Connection.new imap, capabilities

    if block_given? then
      begin
        yield connection
      ensure
        connection.imap.logout
      end
    else
      return connection
    end
  end

  ##
  # Create the mailbox +name+ if it doesn't exist.  Note that this will SELECT
  # the mailbox if it exists.

  def create_mailbox name
    log "LIST #{name}"
    list = imap.list '', name
    return if list
    log "CREATE #{name}"
    imap.create name
  end

  ##
  # Delete and +expunge+ the specified +uids+.

  def delete_messages uids, expunge = true
    log "DELETING [...#{uids.size} uids]"
    imap.store uids, '+FLAGS.SILENT', [:Deleted]
    if expunge then
      log "EXPUNGE"
      imap.expunge
    end
  end

  ##
  # Yields each uid and message as a TMail::Message for +uids+ of MIME type
  # +type+.
  #
  # If there's an exception raised during handling a message the subject,
  # message-id and inspected body are logged.
  #
  # If the block returns nil or false, the message is considered skipped and
  # its uid is not returned in the uid list.  (Hint: next false unless ...)
  #
  # Returns the uids of successfully handled messages.

  def each_message(uids, type) # :yields: TMail::Mail
    parts = mime_parts uids, type

    uids = []

    each_part parts, true do |uid, message|
      mail = TMail::Mail.parse message

      begin
        success = yield uid, mail

        uids << uid if success
      rescue => e
        log e.message
        puts "\t#{e.backtrace.join "\n\t"}" unless $DEBUG # backtrace at bottom
        log "Subject: #{mail.subject}"
        log "Message-Id: #{mail.message_id}"
        p mail.body if verbose?

        raise if $DEBUG
      end
    end

    uids
  end

  ##
  # Yields each message part from +parts+.  If +header+ is true, a complete
  # message is yielded, appropriately joined for use with TMail::Mail.

  def each_part(parts, header = false) # :yields: uid, message
    parts.each do |uid, section|
      sequence = ["BODY[#{section}]"]
      sequence.unshift "BODY[#{section}.MIME]" unless section == 'TEXT'
      sequence.unshift 'BODY[HEADER]' if header

      body = imap.fetch(uid, sequence).first

      sequence = sequence.map { |item| body.attr[item] }

      unless section == 'TEXT' and header then
        sequence[0].sub!(/\r\n\z/, '')
      end

      yield uid, sequence.join
    end
  end

  ##
  # Logs +message+ to $stderr if verbose

  def log(message)
    return unless @verbose
    $stderr.puts "# #{message}"
  end

  ##
  # Retrieves the BODY data item name for the +mime_type+ part from messages
  # +uids+.  Returns an array of uid/part pairs.  If no matching part with
  # +mime_type+ is found the uid is omitted.
  #
  # Returns an Array of uid, section pairs.
  #
  # Use a subsequent Net::IMAP#fetch to retrieve the selected part.

  def mime_parts(uids, mime_type)
    media_type, subtype = mime_type.upcase.split('/', 2)

    structures = imap.fetch uids, 'BODYSTRUCTURE'

    structures.zip(uids).map do |body, uid|
      section = nil
      structure = body.attr['BODYSTRUCTURE']

      case structure
      when Net::IMAP::BodyTypeMultipart then
        parts = structure.parts

        section = parts.each_with_index do |part, index|
          break index if part.media_type == media_type and
                         part.subtype == subtype
        end

        next unless Integer === section
      when Net::IMAP::BodyTypeText, Net::IMAP::BodyTypeBasic then
        section = 'TEXT' if structure.media_type == media_type and
                            structure.subtype == subtype
      end

      [uid, section]
    end.compact
  end

  ##
  # Move the specified +uids+ to a new +destination+ then delete and +expunge+
  # them.  Creates the destination mailbox if it doesn't exist.

  def move_messages uids, destination, expunge = true
    return if uids.empty?
    log "COPY [...#{uids.size} uids]"

    begin
      imap.copy uids, destination
    rescue Net::IMAP::NoResponseError
      # ruby-lang bug #1713
      #raise unless e.response.data.code.name == 'TRYCREATE'
      create_mailbox destination
      imap.copy uids, destination
    end

    delete_messages uids, expunge
  end

  ##
  # Displays Date, Subject and Message-Id from messages in +uids+

  def show_messages(uids)
    return if uids.nil? or (Array === uids and uids.empty?)

    fetch_data = 'BODY.PEEK[HEADER.FIELDS (DATE SUBJECT MESSAGE-ID)]'
    messages = imap.fetch uids, fetch_data
    fetch_data.sub! '.PEEK', '' # stripped by server

    messages.each do |res|
      puts res.attr[fetch_data].delete("\r")
    end
  end

  ##
  # Did the user set --verbose?

  def verbose?
    @verbose
  end

end
