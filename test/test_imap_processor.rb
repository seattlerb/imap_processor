require 'minitest/autorun'
require 'imap_processor'
require 'time'

##
# These tests expect a local IMAP server with a 'test' login with a 'test'
# password.  It's fairly easy to set up dovecot to do this:
#
# In dovecot.conf:
#
#   mail_location = mbox:~/mail:INBOX=~/Mailbox
#   
#   auth default {
#     mechanisms = plain
#   
#     passdb passwd-file {
#       args = scheme=plain username_format=%n /path/to/etc/dovecot/passwd
#     }
#   
#     userdb passwd-file {
#       args = username_format=%n /path/to/etc/dovecot/passwd
#     }
#   }
#
# And in /path/to/etc/dovecot/passwd:
#
#   test:test:<your uid>:<your gid>::/path/to/your/home/dovecot

class TestIMAPProcessor < MiniTest::Unit::TestCase

  def setup
    host, port, username, password = 'localhost', 143, 'test', 'test'

    @ip = IMAPProcessor.new :Host => host, :Port => port,
                            :Username => username, :Password => password,
                            :Verbose => false

    @connection = @ip.connect

    @imap = @connection.imap
    @ip.instance_variable_set :@imap, @imap

    @delim = @imap.list('', 'INBOX').first.delim
  end

  def teardown
    @imap.select 'INBOX'
    uids = @imap.search 'ALL'
    @imap.store uids, '+FLAGS.SILENT', [:Deleted] unless uids.empty?
    @imap.expunge
    @imap.list('', '*').each do |mailbox|
      next if mailbox.name == 'INBOX'
      @imap.delete mailbox.name
    end
    @imap.disconnect
  end

  # pre-run cleanup
  test = self.new nil
  test.setup
  test.teardown

  def test_create_mailbox
    @imap.create "directory#{@delim}"

    assert_equal nil, @ip.create_mailbox('directory')

    refute_nil @ip.create_mailbox('destination') 
    mailbox = @imap.list('', 'destination').first
    assert_equal 'destination', mailbox.name
    assert_equal [:Noinferiors, :Unmarked], mailbox.attr
  end

  def test_delete_messages
    util_message
    uids = util_uids

    @ip.delete_messages uids

    assert_empty util_uids
  end

  def test_delete_messages_no_expunge
    util_message
    uids = util_uids

    @ip.delete_messages uids, false

    uids = util_uids

    refute_empty uids
    assert_includes :Deleted, @imap.fetch(uids, 'FLAGS').first.attr['FLAGS']
  end

  def test_move_messages
    util_message
    uids = util_uids

    @ip.move_messages uids, 'destination'

    assert_equal 0, @imap.search('ALL').length

    assert_equal 1, @imap.list('', 'destination').length
  end

  def test_show_messages
    now = Time.now
    util_message nil, now
    uids = util_uids

    out, = capture_io do
      @ip.show_messages uids
    end

    expected = <<-EXPECTED
Subject: message 1
Date: #{now.rfc2822}
Message-Id: 1

    EXPECTED

    assert_equal expected, out
  end

  def util_message(flags = nil, time = Time.now)
    @count ||= 0
    @count += 1

    message = <<-MESSAGE
From: from@example.com
To: to@example.com
Subject: message #{@count}
Date: #{time.rfc2822}
Message-Id: #{@count}

Hi, this is message number #{@count}
    MESSAGE

    @imap.append 'INBOX', message, flags, time
  end

  def util_uids
    @imap.select 'INBOX'
    @imap.search 'ALL'
  end

end

