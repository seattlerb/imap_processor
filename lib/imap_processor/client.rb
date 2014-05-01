$TESTING = false unless defined? $TESTING
# require 'net/imap'
# require 'yaml'
# require 'imap_sasl_plain'
# require 'optparse'
# require 'enumerator'

require "imap_processor"

##
# This class only exists to transition from IMAPCleanse to imap_processor

class IMAPProcessor::Client < IMAPProcessor

  ##
  # Creates a new IMAPClient from +options+.
  #
  # Options include:
  #   +:Verbose+:: Verbose flag
  #   +:Noop+:: Don't delete anything flag
  #   +:Root+:: IMAP root path
  #   +:Boxes+:: Comma-separated list of mailbox prefixes to search
  #   +:Host+:: IMAP server
  #   +:Port+:: IMAP server port
  #   +:SSL+:: SSL flag
  #   +:Username+:: IMAP username
  #   +:Password+:: IMAP password
  #   +:Auth+:: IMAP authentication type

  def initialize(options)
    super

    @noop = options[:Noop]
    @root = options[:Root]

    root = @root
    root += "/" unless root.empty?

    connect options[:Host], options[:Port], options[:SSL],
            options[:Username], options[:Password], options[:Auth]
  end

  ##
  # Selects messages from mailboxes then marking them with +flags+.  If a
  # block is given it is run after message marking.
  #
  # Unless :Noop was set, then it just prints out what it would do.
  #
  # Automatically called by IMAPClient::run

  def run(message, flags)
    log message

    message_count = 0
    mailboxes = find_mailboxes

    mailboxes.each do |mailbox|
      @mailbox = mailbox
      @imap.select @mailbox
      log "Selected #{@mailbox}"

      messages = find_messages

      next if messages.empty?

      message_count += messages.length

      unless @noop then
        mark messages, flags
      else
        log "Noop - not marking"
      end

      yield messages if block_given?
    end

    log "Done. Found #{message_count} messages in #{mailboxes.length} mailboxes"
  end

  ##
  # Connects to IMAP server +host+ at +port+ using ssl if +ssl+ is true then
  # logs in as +username+ with +password+.  IMAPClient will really only work
  # with PLAIN auth on SSL sockets, sorry.

  def connect(host, port, ssl, username, password, auth = nil)
    @imap = Net::IMAP.new host, port, ssl, nil, false
    log "Connected to #{host}:#{port}"

    if auth.nil? then
      auth_caps = @imap.capability.select { |c| c =~ /^AUTH/ }
      raise "Couldn't find a supported auth type" if auth_caps.empty?
      auth = auth_caps.first.sub(/AUTH=/, '')
    end

    auth = auth.upcase
    log "Trying #{auth} authentication"
    @imap.authenticate auth, username, password
    log "Logged in as #{username}"
  end

  ##
  # Finds mailboxes with messages that were selected by the :Boxes option.

  def find_mailboxes
    mailboxes = @imap.list(@root, "*")

    if mailboxes.nil? then
      log "Found no mailboxes under #{@root.inspect}, you may have an incorrect root"
      return []
    end

    mailboxes.reject! { |mailbox| mailbox.attr.include? :Noselect }
    mailboxes.map! { |mailbox| mailbox.name }

    @box_re = /^#{Regexp.escape @root}#{Regexp.union(*@boxes)}/

    mailboxes.reject! { |mailbox| mailbox !~ @box_re }
    mailboxes = mailboxes.sort_by { |m| m.downcase }
    log "Found #{mailboxes.length} mailboxes to search:"
    mailboxes.each { |mailbox| log "\t#{mailbox}" } if @verbose
    return mailboxes
  end

  ##
  # Searches for messages matching +query+ in the selected mailbox
  # (see Net::IMAP#select).  Logs 'Scanning for +message+' before searching.

  def search(query, message)
    log "  Scanning for #{message}"
    messages = @imap.search query
    log "    Found #{messages.length} messages"
    return messages
  end

  ##
  # Marks +messages+ in the currently selected mailbox with +flags+
  # (see Net::IMAP#store).

  def mark(messages, flags)
    messages.each_slice(500) do |chunk|
      @imap.store chunk, '+FLAGS.SILENT', flags
    end
    log "Marked messages with flags"
  end
end
