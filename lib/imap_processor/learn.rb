require 'imap_processor/client'
require 'fileutils'

require 'rubygems'

begin
  require 'rbayes'
rescue LoadError
  # ignoring
  class RBayes
    def initialize *args
      # nothing to do
    end
  end
end

##
# IMAPLearn flags messages per-folder based on what you've flagged before.
#
# aka part three of my Plan for Total Email Domination.

class IMAPProcessor::Learn < IMAPProcessor::Client

  ##
  # IMAP keyword for learned messages

  LEARN_KEYWORD = 'IMAPLEARN_FLAGGED'

  ##
  # IMAP keyword for tasty messages

  TASTY_KEYWORD = LEARN_KEYWORD + '_TASTY'

  ##
  # IMAP keyword for bland messages

  BLAND_KEYWORD = LEARN_KEYWORD + '_BLAND'

  ##
  # Handles processing of +args+.

  def self.process_args(args)
    @@options[:Threshold] = [0.85, 'Tastiness threshold not set']

    super __FILE__, args, {} do |opts, options|
      opts.on("-t", "--threshold THRESHOLD",
              "Flag messages more tasty than THRESHOLD",
              "Default: #{options[:Threshold].inspect}",
              "Options file name: Threshold", Float) do |threshold|
        options[:Threshold] = threshold
      end
    end
  end

  ##
  # Creates a new IMAPLearn from +options+.
  #
  # Options include:
  #   +:Threshold+:: Tastiness threshold for flagging
  #
  # and all options from IMAPClient

  def initialize(options)
    super

    @db_root = File.join '~', '.imap_learn',
                      "#{options[:User]}@#{options[:Host]}:#{options[:Port]}"
    @db_root = File.expand_path @db_root

    @threshold = options[:Threshold]

    @classifiers = Hash.new do |h,k|
      filter_db = File.join @db_root, "#{k}.db"
      FileUtils.mkdir_p File.dirname(filter_db)
      h[k] = RBayes.new filter_db
    end

    @unlearned_flagged = []
    @tasty_unflagged = []
    @bland_flagged = []
    @tasty_unlearned = []
    @bland_unlearned = []

    @noop = false
  end

  ##
  # Flags tasty messages from all selected mailboxes.

  def run
    log "Flagging tasty messages"

    message_count = 0
    mailboxes = find_mailboxes

    mailboxes.each do |mailbox|
      @mailbox = mailbox
      @imap.select @mailbox
      log "Selected #{@mailbox}"

      message_count += process_unlearned_flagged
      message_count += process_tasty_unflagged
      message_count += process_bland_flagged
      message_count += process_unlearned
    end

    log "Done. Found #{message_count} messages in #{mailboxes.length} mailboxes"
  end

  private

  ##
  # Returns an Array of tasty message sequence numbers.

  def unlearned_flagged_in_curr
    log "Finding unlearned, flagged messages"

    @unlearned_flagged = @imap.search [
      'FLAGGED',
      'NOT', 'KEYWORD', LEARN_KEYWORD
    ]

    update_db @unlearned_flagged, :add_tasty

    @unlearned_flagged.length
  end

  ##
  # Returns an Array of message sequence numbers that should be marked as
  # bland.

  def tasty_unflagged_in_curr
    log "Finding messages re-marked bland"

    @bland_flagged = @imap.search [
     'NOT', 'FLAGGED',
     'KEYWORD', TASTY_KEYWORD
    ]

    update_db @tasty_unflagged, :remove_tasty, :add_bland
    
    @bland_flagged.length
  end

  ##
  # Returns an Array of tasty message sequence numbers that should be marked
  # as tasty.

  def bland_flagged_in_curr
    log "Finding messages re-marked tasty"
    @bland_flagged = @imap.search [
      'FLAGGED',
      'KEYWORD', BLAND_KEYWORD
    ]

    update_db @bland_flagged, :remove_bland, :add_tasty

    @bland_flagged.length
  end

  ##
  # Returns two Arrays, one of tasty message sequence numbers and one of bland
  # message sequence numbers.

  def unlearned_in_curr
    log "Learning new, unmarked messages"
    unlearned = @imap.search [
      'NOT', 'KEYWORD', LEARN_KEYWORD
    ]

    tasty = []
    bland = []

    chunk unlearned do |messages|
      bodies = @imap.fetch messages, 'RFC822'
      bodies.each do |body|
        text = body.attr['RFC822']
        bucket = classify(text) ? tasty : bland
        bucket << body.seqno
      end
    end

    update_db tasty, :add_tasty
    update_db bland, :add_bland

    tasty.length + bland.length
  end

  def chunk(messages, size = 20)
    messages = messages.dup

    until messages.empty? do
      chunk = messages.slice! 0, size
      yield chunk
    end
  end

  ##
  # Returns true if +text+ is "tasty"

  def classify(text)
    rating = @classifiers[@mailbox].rate text
    rating > @threshold
  end

  def update_db(messages, *actions)
    chunk messages do |chunk|
      bodies = @imap.fetch chunk, 'RFC822'
      bodies.each do |body|
        text = body.attr['RFC822']
        actions.each do |action|
          @classifiers[@mailbox].update_db_with text, action
          case action
          when :add_bland then
            @imap.store body.seqno, '+FLAG.SILENT',
                        [LEARN_KEYWORD, BLAND_KEYWORD]
          when :add_tasty then
            @imap.store body.seqno, '+FLAG.SILENT',
                        [:Flagged, LEARN_KEYWORD, TASTY_KEYWORD]
          when :remove_bland then
            @imap.store body.seqno, '-FLAG.SILENT', [BLAND_KEYWORD]
          when :remove_tasty then
            @imap.store body.seqno, '-FLAG.SILENT', [TASTY_KEYWORD]
          end
        end
      end
    end
  end

end

