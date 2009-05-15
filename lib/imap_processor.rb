require 'rubygems'
require 'optparse'
require 'net/imap'
require 'imap_sasl_plain'

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

class IMAPProcessor

  ##
  # The version of IMAPProcessor you are using

  VERSION = '1.0.1'

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
              "Options file name: MoveTo") do |mailbox|
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
  #     super __FILE__, args, required_options do |opts, options|
  #       opts.banner << "Explain my_processor's executable"
  #   
  #       opts.on(      "--move=MAILBOX",
  #               "Mailbox to move message to",
  #               "Default: #{options[:MoveTo].inspect}",
  #               "Options file name: MoveTo") do |mailbox|
  #         options[:MoveTo] = mailbox
  #       end
  #     end
  #   end

  def self.process_args(processor_file, args,
                        required_options = {}) # :yield: OptionParser
    opts_file_name = File.basename processor_file, '.rb'
    opts_file = File.expand_path "~/.#{opts_file_name}"
    options = @@options.dup

    if required_options then
      required_options.each do |option, (default, message)|
        raise ArgumentError,
              "required_options message is missing for #{option}" if
          default.nil? and message.nil?
      end
    end

    if File.exist? opts_file then
      unless File.stat(opts_file).mode & 077 == 0 then
        $stderr.puts "WARNING! #{opts_file} is group/other readable or writable!"
        $stderr.puts "WARNING! I'm not doing a thing until you fix it!"
        exit 1
      end

      options.merge! YAML.load_file(opts_file)
    end

    options[:SSL]      ||= true
    options[:Username] ||= ENV['USER']
    options[:Root]     ||= nil
    options[:Verbose]  ||= false
    options[:Debug]    ||= false

    required_options.each do |k,(v,m)|
      options[k]       ||= v
    end

    opts = OptionParser.new do |opts|
      opts.program_name = File.basename $0
      opts.banner = "Usage: #{opts.program_name} [options]\n\n"

      opts.separator ''
      opts.separator 'Connection options:'

      opts.on("-H", "--host HOST",
              "IMAP server host",
              "Default: #{options[:Host].inspect}",
              "Options file name: Host") do |host|
        options[:Host] = host
      end

      opts.on("-P", "--port PORT",
              "IMAP server port",
              "Default: The correct port SSL/non-SSL mode",
              "Options file name: Port") do |port|
        options[:Port] = port
      end

      opts.on("-s", "--[no-]ssl",
              "Use SSL for IMAP connection",
              "Default: #{options[:SSL].inspect}",
              "Options file name: SSL") do |ssl|
        options[:SSL] = ssl
      end

      opts.on(      "--[no-]debug",
              "Display Net::IMAP debugging info",
              "Default: #{options[:Debug].inspect}",
              "Options file name: Debug") do |debug|
        options[:Debug] = debug
      end

      opts.separator ''
      opts.separator 'Login options:'

      opts.on("-u", "--username USERNAME",
              "IMAP username",
              "Default: #{options[:Username].inspect}",
              "Options file name: Username") do |username|
        options[:Username] = username
      end

      opts.on("-p", "--password PASSWORD",
              "IMAP password",
              "Default: Read from ~/.#{opts_file_name}",
              "Options file name: Password") do |password|
        options[:Password] = password
      end

      authenticators = Net::IMAP.send :class_variable_get, :@@authenticators
      auth_types = authenticators.keys.sort.join ', '
      opts.on("-a", "--auth AUTH", auth_types,
              "IMAP authentication type override",
              "Authentication type will be auto-",
              "discovered",
              "Default: #{options[:Auth].inspect}",
              "Options file name: Auth") do |auth|
        options[:Auth] = auth
      end

      opts.separator ''
      opts.separator "IMAP options:"

      opts.on("-r", "--root ROOT",
              "Root of mailbox hierarchy",
              "Default: #{options[:Root].inspect}",
              "Options file name: Root") do |root|
        options[:Root] = root
      end

      opts.on("-b", "--boxes BOXES", Array,
              "Comma-separated list of mailbox names",
              "to search",
              "Default: #{options[:Boxes].inspect}",
              "Options file name: Boxes") do |boxes|
        options[:Boxes] = boxes
      end

      opts.on("-v", "--[no-]verbose",
              "Be verbose",
              "Default: #{options[:Verbose].inspect}",
              "Options file name: Verbose") do |verbose|
        options[:Verbose] = verbose
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

Options may also be set in the options file ~/.#{opts_file_name}

Example ~/.#{opts_file_name}:
\tHost=mail.example.com
\tPassword=my password

      EOF
    end

    opts.parse! args

    options[:Port] ||= options[:SSL] ? 993 : 143

    if options[:Host].nil? or
       options[:Password].nil? or
       options[:Boxes].nil? or
       required_options.any? { |k,(v,m)| options[k].nil? } then
      $stderr.puts opts
      $stderr.puts
      $stderr.puts "Host name not set" if options[:Host].nil?
      $stderr.puts "Password not set"  if options[:Password].nil?
      $stderr.puts "Boxes not set"     if options[:Boxes].nil?
      required_options.each do |option_name, (option_value, missing_message)|
        $stderr.puts missing_message if options[option_name].nil?
      end
      exit 1
    end

    return options
  end

  ##
  # Sets up an IMAP processor's options then calls its \#run method.

  def self.run(args = ARGV, &block)
    options = process_args args
    client = new(options, &block)
    client.run
  rescue SystemExit
    raise
  rescue Exception => e
    $stderr.puts "Failed to finish with exception: #{e.class}:#{e.message}"
    $stderr.puts "\t#{e.backtrace.join "\n\t"}"

    exit 1
  ensure
    client.imap.logout if client
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
  # Connects to IMAP server +host+ at +port+ using ssl if +ssl+ is true then
  # logs in as +username+ with +password+.  IMAPProcessor is only known to
  # work with PLAIN auth on SSL sockets.
  #
  # Returns a Connection object.

  def connect(host, port, ssl, username, password, auth = nil)
    imap = Net::IMAP.new host, port, ssl
    log "Connected to imap://#{host}:#{port}/"

    capability = imap.capability

    log "Capabilities: #{capability.join ', '}"

    auth_caps = capability.select { |c| c =~ /^AUTH/ }

    if auth.nil? then
      raise "Couldn't find a supported auth type" if auth_caps.empty?
      auth = auth_caps.first.sub(/AUTH=/, '')
    end

    auth = auth.upcase
    log "Trying #{auth} authentication"
    imap.authenticate auth, username, password
    log "Logged in as #{username}"

    Connection.new imap, capability
  end

  ##
  # Yields each uid and message as a TMail::Message for +uids+ of MIME type
  # +type+.
  #
  # If there's an exception raised during handling a message the subject,
  # message-id and inspected body are logged.
  #
  # Returns the uids of successfully handled messages.

  def each_message(uids, type) # :yields: TMail::Mail
    parts = mime_parts uids, type

    uids = []

    each_part parts, true do |uid, message|
      mail = TMail::Mail.parse message

      begin
        yield uid, mail

        uids << uid
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

      body = @imap.fetch(uid, sequence).first

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

    structures = @imap.fetch uids, 'BODYSTRUCTURE'

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
  # Did the user set --verbose?

  def verbose?
    @verbose
  end

end

