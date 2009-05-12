require 'time'
require 'net/imap'

class Time

  ##
  # Formats this Time as an IMAP-style date.

  def imapdate
    strftime '%d-%b-%Y'
  end

  ##
  # Formats this Time as an IMAP-style datetime.
  #
  # RFC 2060 doesn't specify the format of its times.  Unfortunately it is
  # almost but not quite RFC 822 compliant.
  #--
  # Go Mr. Leatherpants!

  def imapdatetime
    strftime '%d-%b-%Y %H:%M %Z'
  end

end

##
# RFC 2595 PLAIN Authenticator for Net::IMAP.  Only for use with SSL (but not
# enforced).

class Net::IMAP::PlainAuthenticator

  ##
  # From RFC 2595 Section 6. PLAIN SASL Authentication
  #
  #  The mechanism consists of a single message from the client to the
  #  server.  The client sends the authorization identity (identity to
  #  login as), followed by a US-ASCII NUL character, followed by the
  #  authentication identity (identity whose password will be used),
  #  followed by a US-ASCII NUL character, followed by the clear-text
  #  password.  The client may leave the authorization identity empty to
  #  indicate that it is the same as the authentication identity.

  def process(data)
    return [@user, @user, @password].join("\0")
  end

  private

  ##
  # Creates a new PlainAuthenticator that will authenticate with +user+ and
  # +password+.

  def initialize(user, password)
    @user = user
    @password = password
  end

end

if defined? OpenSSL then
  Net::IMAP.add_authenticator 'PLAIN', Net::IMAP::PlainAuthenticator
end


